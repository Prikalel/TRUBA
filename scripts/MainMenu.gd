extends CanvasLayer
# Title screen overlay for the main scene (scenes/test2.tscn).
#
# Behaviour requested for the main menu:
#   * On startup it freezes the game (get_tree().paused = true) so the player
#     can't look around / swing the weapon while the title is up, and loops the
#     main-menu jingle (assets/sounds/main-menu.mp3).
#   * Clicking "Начать" simply removes the menu and lets the game run. Because
#     main-menu.mp3 is specifically the *main menu* music, it is stopped here.
#   * "Настройки" opens an in-place Settings overlay (sound + cosmetic graphics).
#   * The 💀 button opens the project's VK page in a new browser tab.
#
# This CanvasLayer is configured with pause_mode = PROCESS (see test2.tscn) so
# it - and its music + buttons - keep working while the rest of the tree is paused.
#
# The Settings button, Settings panel and the VK button are all built in code in
# _ready() on purpose: it keeps us from hand-editing the large test2.tscn scene.
# Only the existing TitleLabel / StartButton / MenuMusic live in the .tscn.

onready var _music: AudioStreamPlayer = $MenuMusic
onready var _button: Button = $MenuControl/VBox/StartButton
onready var _vbox: VBoxContainer = $MenuControl/VBox
onready var _menu_control: Control = $MenuControl

# Index of the Master bus. Everything in the game routes through it, so tweaking
# it here controls ALL audio in real time.
var _master_bus := -1
# Settings overlay, built dynamically in _ready().
var _settings_panel: Panel

func _ready() -> void:
	# Freeze gameplay until the player presses "Начать".
	get_tree().paused = true
	# The Inventory (a child of the Player) captures the mouse in its own _ready,
	# which runs before this node - so free + show the OS cursor, otherwise the
	# Start button can't be clicked on the title screen.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# main-menu.mp3 is imported with loop=true; enforce it in code too so the
	# track keeps looping even if the asset is ever re-imported without it.
	if _music.stream is AudioStreamMP3:
		_music.stream.loop = true
	_music.play()
	_button.connect("pressed", self, "_on_start_pressed")

	_master_bus = AudioServer.get_bus_index("Master")

	# Build the rest of the menu UI in code so we don't hand-edit test2.tscn.
	_add_settings_button()
	_add_vk_button()
	_build_settings_panel()

# Adds the "Настройки" button right below StartButton inside the title VBox.
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
	var emoji_font := DynamicFont.new()
	var font_data = load("res://assets/fonts/NotoEmoji-Regular.ttf")
	if font_data is DynamicFontData:
		emoji_font.font_data = font_data
	emoji_font.size = 32
	vk_btn.set("custom_fonts/font", emoji_font)
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

	var title := Label.new()
	title.text = "Настройки / Settings"
	title.align = Label.ALIGN_CENTER
	column.add_child(title)

	# --- Sound: drives global audio via the Master bus (real, functional). ---
	_add_slider_row(column, "Звук / Sound", 0.0, 100.0, 100.0, "_on_sound_changed")

	# --- Cosmetic graphics sliders (PLACEHOLDERS). They are draggable but do
	# nothing yet - a separate task wires them up to actual graphics options. ---
	_add_slider_row(column, "Яркость / Brightness", 0.0, 100.0, 100.0, "_on_cosmetic_changed")
	_add_slider_row(column, "Тени / Shadows", 0.0, 100.0, 100.0, "_on_cosmetic_changed")
	_add_slider_row(column, "Текстуры / Texture Quality", 0.0, 100.0, 100.0, "_on_cosmetic_changed")

	var back_btn := Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "Назад / Back"
	back_btn.rect_min_size = Vector2(260, 60)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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

# "если нажать на неё - просто убрать менюшку": dismiss the title screen and let
# the game run.
func _on_start_pressed() -> void:
	_music.stop()
	# Re-capture the cursor for FPS mouse-look (the Inventory expects CAPTURED).
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = false
	# Resume at the saved level if one exists (browser tab closed & reopened);
	# change_scene frees the menu and test2.tscn automatically. Guard with
	# ResourceLoader.exists so a corrupt/missing save never hard-crashes.
	if SaveSystem.has_save():
		var saved := SaveSystem.get_saved_level()
		if saved != "" and ResourceLoader.exists(saved):
			get_tree().change_scene(saved)
			return
	# No (valid) save — start in the current scene as before.
	queue_free()

func _on_settings_pressed() -> void:
	# Hide the title VBox (title + start + settings button) and show settings.
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
