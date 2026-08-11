 extends CanvasLayer
# Main-menu overlay for the title scene (scenes/test2.tscn).
#
# The title scene IS level 1 of the game. While the menu is up the whole tree
# is paused (get_tree().paused = true) and the main-menu jingle loops.
#
# Buttons:
#   * "Начать"      — opens a numbered level-select grid. Every level is always
#                     unlocked. Selecting level 1 just dismisses the menu and
#                     lets the current scene (test2) run; selecting any other
#                     level change_scene's to it WITHOUT recording progress.
#   * "Продолжить" — shown only when a save exists. Resumes at the saved level
#                     (the previous "Начать" behaviour).
#   * "Настройки"  — in-place Settings overlay (sound + cosmetic graphics).
#   * 💀            — opens the project's VK page in a new browser tab.
#
# Progress indicator: the save always points at the player's CURRENT / last
# reached level (every in-level SceneTransitionArea writes it on transition).
# When a save exists, a ⭐ (drawn with NotoEmoji) is shown next to that level's
# number in the grid AND the Continue button shows its number. No save → no
# star on any level and no Continue button.
#
# This CanvasLayer is pause_mode = PROCESS (see test2.tscn) so it - and its
# music + buttons - keep working while the rest of the tree is paused.
#
# The Settings button, Settings panel, VK button, Continue button and the whole
# level grid are built in code in _ready() on purpose: it keeps us from
# hand-editing the large test2.tscn scene. Only TitleLabel / StartButton /
# MenuMusic live in the .tscn.
#
# Level chain (loops back to the title scene):
#   1 test2.tscn -> 2 part1_horror.tscn -> 3 test3.tscn
#                -> 4 test.tscn -> 5 new.tscn -> (back to) 1 test2.tscn

# Ordered list of level scenes by number (index + 1 == level number). Single
# source of truth for the level grid, the ⭐ indicator and the Continue label.
const LEVELS := [
	"res://scenes/test2.tscn",                               # 1 (title scene)
	"res://imported_from_part1/scenes/part1_horror.tscn",    # 2
	"res://scenes/test3.tscn",                               # 3
	"res://scenes/test.tscn",                                # 4
	"res://scenes/new/new.tscn",                             # 5
]
# Resource path of level 1 — selecting it just dismisses the menu instead of
# reloading the scene we are already in.
const LEVEL_TEST2 := "res://scenes/test2.tscn"

onready var _music: AudioStreamPlayer = $MenuMusic
onready var _button: Button = $MenuControl/VBox/StartButton
onready var _vbox: VBoxContainer = $MenuControl/VBox
onready var _menu_control: Control = $MenuControl

# Index of the Master bus. Everything in the game routes through it, so tweaking
# it here controls ALL audio in real time.
var _master_bus := -1
# Settings overlay, built dynamically in _ready().
var _settings_panel: Panel
# Level-select grid overlay, built dynamically in _ready().
var _level_grid_panel: Control
# "Продолжить" button (null when there is no save).
var _continue_button: Button
# Font used for every label / button on the Settings overlay (Russian text).
var _settings_font: DynamicFont


func _ready() -> void:
	# Freeze gameplay until the player starts a level.
	get_tree().paused = true
	# The Inventory (a child of the Player) captures the mouse in its own _ready,
	# which runs before this node - so free + show the OS cursor, otherwise the
	# buttons can't be clicked on the title screen.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# main-menu.mp3 is imported with loop=true; enforce it in code too so the
	# track keeps looping even if the asset is ever re-imported without it.
	if _music.stream is AudioStreamMP3:
		_music.stream.loop = true
	_music.play()
	# "Начать" now opens the level grid instead of resuming instantly.
	_button.connect("pressed", self, "_on_start_pressed")

	_master_bus = AudioServer.get_bus_index("Master")

	# Build the rest of the menu UI in code so we don't hand-edit test2.tscn.
	# Order matters: Continue must sit between Start and Settings in the VBox,
	# so it is added before the Settings button.
	_add_continue_button()
	_add_settings_button()
	_add_vk_button()
	_build_settings_panel()
	_build_level_grid()


# --- Title-screen buttons -----------------------------------------------------

# "Начать" — open the numbered level-select grid. Does NOT start the game yet;
# the player picks a level (or presses Back) there.
func _on_start_pressed() -> void:
	_vbox.visible = false
	_level_grid_panel.visible = true


# "Продолжить" — resume at the saved level (the previous "Начать" behaviour).
# Only connected/shown when a save exists.
func _on_continue_pressed() -> void:
	if not SaveSystem.has_save():
		return
	var saved := SaveSystem.get_saved_level()
	if saved == "" or not ResourceLoader.exists(saved):
		return
	_begin_play()
	if saved == LEVEL_TEST2:
		# Saved at the title scene itself — just dismiss the menu and play L1.
		queue_free()
	else:
		get_tree().change_scene(saved)


# --- Level-select grid --------------------------------------------------------

# Build the numbered level grid. Every level is always selectable. A ⭐ is
# drawn next to the saved level's number (NotoEmoji) when a save exists.
func _build_level_grid() -> void:
	_level_grid_panel = Control.new()
	_level_grid_panel.name = "LevelGridPanel"
	_level_grid_panel.anchor_right = 1.0
	_level_grid_panel.anchor_bottom = 1.0
	_level_grid_panel.visible = false
	_menu_control.add_child(_level_grid_panel)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.035, 0.035, 0.045, 1)
	_level_grid_panel.add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	_level_grid_panel.add_child(center)

	var column := VBoxContainer.new()
	column.add_constant_override("separation", 28)
	center.add_child(column)

	var title := Label.new()
	title.text = "Выберите уровень"
	title.align = Label.ALIGN_CENTER
	title.set("custom_fonts/font", _make_bookxel_font(40))
	column.add_child(title)

	var saved_idx := _saved_level_index()
	var has_save := SaveSystem.has_save()
	var number_font := _make_bookxel_font(52)
	var star_font := _make_emoji_font(40)

	var grid := GridContainer.new()
	grid.columns = LEVELS.size()
	grid.add_constant_override("hseparation", 22)
	grid.add_constant_override("vseparation", 22)
	column.add_child(grid)

	for i in range(LEVELS.size()):
		# Each grid cell is an HBox: the clickable number button + an optional ⭐.
		var cell := HBoxContainer.new()
		cell.add_constant_override("separation", 6)
		var btn := Button.new()
		btn.name = "Level%d" % (i + 1)
		btn.text = str(i + 1)
		btn.rect_min_size = Vector2(120, 120)
		btn.theme = _button.theme
		btn.set("custom_fonts/font", number_font)
		btn.connect("pressed", self, "_on_level_selected", [i])
		cell.add_child(btn)
		# ⭐ next to the number — only for the saved level and only when a save
		# exists. Hidden Controls are skipped by HBoxContainer layout, so the
		# other level buttons stay compact.
		var star := Label.new()
		star.name = "Star"
		star.text = "⭐"
		star.valign = Label.VALIGN_CENTER
		star.set("custom_fonts/font", star_font)
		star.visible = has_save and i == saved_idx
		cell.add_child(star)
		grid.add_child(cell)

	var back_btn := Button.new()
	back_btn.name = "GridBackButton"
	back_btn.text = "Назад"
	back_btn.rect_min_size = Vector2(220, 60)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.theme = _button.theme
	back_btn.set("custom_fonts/font", _button.get("custom_fonts/font"))
	back_btn.connect("pressed", self, "_on_grid_back_pressed")
	column.add_child(back_btn)


# A numbered level was picked from the grid.
func _on_level_selected(level_index: int) -> void:
	var path: String = LEVELS[level_index]
	if path == LEVEL_TEST2:
		# Level 1 is the scene we're already in — just dismiss the menu and play.
		_begin_play()
		queue_free()
		return
	# Jumping to another level from the grid is "free play": load it but do NOT
	# record progress (no SaveSystem.save_level). Real transitions inside the
	# levels still save as the player progresses.
	if not ResourceLoader.exists(path):
		push_error("MainMenu: level scene not found: %s" % path)
		return
	_begin_play()
	get_tree().change_scene(path)


# "Назад" from the level grid — back to the title buttons.
func _on_grid_back_pressed() -> void:
	_level_grid_panel.visible = false
	_vbox.visible = true


# --- Continue button ----------------------------------------------------------

func _add_continue_button() -> void:
	if not SaveSystem.has_save():
		return
	var btn := Button.new()
	btn.name = "ContinueButton"
	var idx := _saved_level_index()
	if idx >= 0:
		btn.text = "Продолжить (уровень %d)" % (idx + 1)
	else:
		btn.text = "Продолжить"
	btn.rect_min_size = Vector2(260, 80)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.theme = _button.theme
	btn.set("custom_fonts/font", _button.get("custom_fonts/font"))
	btn.connect("pressed", self, "_on_continue_pressed")
	_vbox.add_child(btn)
	_continue_button = btn


# --- Shared helpers -----------------------------------------------------------

# Common "leave the menu and hand control to the game" steps: stop the jingle,
# un-pause the tree and re-capture the cursor for FPS mouse-look.
func _begin_play() -> void:
	_music.stop()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = false


# Index (0-based) of the saved level inside LEVELS, or -1 if there is no save
# or the saved path isn't one of the known levels.
func _saved_level_index() -> int:
	if not SaveSystem.has_save():
		return -1
	var saved := SaveSystem.get_saved_level()
	for i in range(LEVELS.size()):
		if LEVELS[i] == saved:
			return i
	return -1


func _make_bookxel_font(size: int) -> DynamicFont:
	var f := DynamicFont.new()
	var data = load("res://bookxel.ttf")
	if data is DynamicFontData:
		f.font_data = data
	f.size = size
	return f


func _make_emoji_font(size: int) -> DynamicFont:
	# NotoEmoji is the only bundled font that actually renders emoji glyphs
	# (⭐, 💀) instead of empty "tofu" boxes.
	var f := DynamicFont.new()
	var data = load("res://assets/fonts/NotoEmoji-Regular.ttf")
	if data is DynamicFontData:
		f.font_data = data
	f.size = size
	return f


# --- Settings overlay ---------------------------------------------------------

# Adds the "Настройки" button right below StartButton (and Continue) inside the
# title VBox.
func _add_settings_button() -> void:
	var settings_btn := Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = "Настройки"
	settings_btn.rect_min_size = Vector2(260, 80)
	settings_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Reuse the same look as the Start button.
	settings_btn.theme = _button.theme
	var start_font = _button.get("custom_fonts/font")
	if start_font != null:
		settings_btn.set("custom_fonts/font", start_font)
	settings_btn.connect("pressed", self, "_on_settings_pressed")
	_vbox.add_child(settings_btn)


# Small 💀 button in the corner. The skull emoji is drawn with NotoEmoji so it
# actually renders as a glyph instead of an empty "tofu" box.
func _add_vk_button() -> void:
	var vk_btn := Button.new()
	vk_btn.name = "VKButton"
	vk_btn.text = "💀"
	vk_btn.rect_min_size = Vector2(64, 64)
	# Anchor to the bottom-right corner of the screen.
	vk_btn.anchor_left = 1.0
	vk_btn.anchor_right = 1.0
	vk_btn.anchor_top = 1.0
	vk_btn.anchor_bottom = 1.0
	vk_btn.margin_left = -84.0
	vk_btn.margin_top = -84.0
	vk_btn.margin_right = -20.0
	vk_btn.margin_bottom = -20.0
	vk_btn.set("custom_fonts/font", _make_emoji_font(32))
	vk_btn.connect("pressed", self, "_open_vk")
	_menu_control.add_child(vk_btn)


# Builds the Settings overlay: a full-screen Panel with a centered column of
# labelled sliders + a Back button. Hidden until "Настройки" is pressed.
func _build_settings_panel() -> void:
	_settings_panel = Panel.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.anchor_right = 1.0
	_settings_panel.anchor_bottom = 1.0
	_settings_panel.visible = false
	_menu_control.add_child(_settings_panel)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	_settings_panel.add_child(center)

	var column := VBoxContainer.new()
	column.rect_min_size = Vector2(420, 420)
	column.add_constant_override("separation", 16)
	center.add_child(column)

	# Settings overlay uses the bookxel 2x font and Russian-only labels.
	_settings_font = load("res://assets/fonts/bookxel-font-2x.tres") as DynamicFont
	var title := Label.new()
	title.text = "Настройки"
	title.align = Label.ALIGN_CENTER
	if _settings_font != null:
		title.set("custom_fonts/font", _settings_font)
	column.add_child(title)

	# --- Sound: drives global audio via the Master bus (real, functional). ---
	_add_slider_row(column, "Звук", 0.0, 100.0, 100.0, "_on_sound_changed")

	# --- Cosmetic graphics sliders (PLACEHOLDERS). They are draggable but do
	# nothing yet - a separate task wires them up to actual graphics options. ---
	_add_slider_row(column, "Яркость", 0.0, 100.0, 100.0, "_on_cosmetic_changed")
	_add_slider_row(column, "Тени", 0.0, 100.0, 100.0, "_on_cosmetic_changed")
	_add_slider_row(column, "Текстуры", 0.0, 100.0, 100.0, "_on_cosmetic_changed")

	var back_btn := Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "Назад"
	back_btn.rect_min_size = Vector2(260, 60)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if _settings_font != null:
		back_btn.set("custom_fonts/font", _settings_font)
	back_btn.connect("pressed", self, "_on_back_pressed")
	column.add_child(back_btn)


# Helper: one labelled slider row inside the settings column.
func _add_slider_row(parent: Control, label_text: String,
		min_val: float, max_val: float, default_val: float,
		handler_name: String) -> void:
	var row := VBoxContainer.new()
	row.add_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label_text
	if _settings_font != null:
		lbl.set("custom_fonts/font", _settings_font)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.rect_min_size = Vector2(360, 28)
	row.add_child(slider)
	parent.add_child(row)
	if handler_name != "":
		slider.connect("value_changed", self, handler_name)


func _on_settings_pressed() -> void:
	# Hide the title VBox (title + start + continue + settings button) and show
	# settings.
	_vbox.visible = false
	_settings_panel.visible = true


func _on_back_pressed() -> void:
	_settings_panel.visible = false
	_vbox.visible = true


# Real handler: drive the Master bus volume from a 0..100 slider.
func _on_sound_changed(value: float) -> void:
	if _master_bus < 0:
		return
	if value <= 0.0:
		AudioServer.set_bus_mute(_master_bus, true)
	else:
		AudioServer.set_bus_mute(_master_bus, false)
		AudioServer.set_bus_volume_db(_master_bus, linear2db(value / 100.0))


# Placeholder for the cosmetic graphics sliders - intentionally a no-op.
func _on_cosmetic_changed(_value: float) -> void:
	pass


# Open the project's VK page in a new browser tab.
# The JavaScript singleton only exists in the HTML5 export, so look it up through
# Engine (not the `JavaScript` class name directly) to keep this script parseable
# on desktop / editor builds and never crash there.
func _open_vk() -> void:
	var url := "https://vk.ru/fetidity"
	if OS.has_feature("HTML5"):
		var js = null
		if Engine.has_singleton("JavaScript"):
			js = Engine.get_singleton("JavaScript")
		if js != null:
			js.eval("window.open('%s', '_blank')" % url, true)
		else:
			OS.shell_open(url)
	else:
		OS.shell_open(url)
