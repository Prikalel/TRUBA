extends Control
# Center-screen "interaction cursor" for heavy, drag-able props (boxes, crates,
# etc.).
#
# Why a dedicated screen-space icon instead of the floating "E" prompt
# (FloatingPrompt) that pickups use: while an object is carried it is reparented
# onto the player (see Player.get_is_dragging), so a world-space prompt attached
# to the prop would jitter and clip. A single icon pinned to the middle of the
# viewport stays readable for the whole grab.
#
# Three mutually-exclusive states, driven by Player:
#   show_start()  -> T_start_hold_interaction.png (open hand : "you can grab")
#   show_hold()   -> T_hold_interaction.png      (clenched hand : "you are holding")
#   hide_cursor() -> nothing on screen
#
# Attach as a Control child of the player. It covers the whole screen but never
# consumes input (mouse_filter = IGNORE), it is pure decoration.

const START_ICON_PATH := "res://assets/textures/ui/interact_icons/T_start_hold_interaction.png"
const HOLD_ICON_PATH := "res://assets/textures/ui/interact_icons/T_hold_interaction.png"

var _icon: TextureRect = null
var _start_icon: Texture = null
var _hold_icon: Texture = null

func _ready() -> void:
	# Decorative overlay: never swallow clicks/keys from the game.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# DOWNGRADE NOTE: Godot 3.x has no PRESET_FULL_RECT (that is Godot 4). Setting
	# the anchors explicitly fills the whole viewport, the same way the Inventory
	# Control does (a Control parented under a 3D node anchors to the root window).
	anchor_right = 1.0
	anchor_bottom = 1.0
	margin_left = 0
	margin_top = 0
	margin_right = 0
	margin_bottom = 0

	_start_icon = load(START_ICON_PATH)
	_hold_icon = load(HOLD_ICON_PATH)

	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.texture = _start_icon
	# Let the rect fill the whole screen, then keep the source texture at its
	# native size centered in it (resolution-independent centering).
	_icon.expand = true
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_icon.anchor_right = 1.0
	_icon.anchor_bottom = 1.0
	_icon.margin_left = 0
	_icon.margin_top = 0
	_icon.margin_right = 0
	_icon.margin_bottom = 0
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	# Hidden until the player actually has something drag-able in range.
	hide()

# "You can grab this" - open-hand icon. Cheap to call every frame: only sets the
# texture when needed and only shows when currently hidden.
func show_start() -> void:
	if _icon == null:
		return
	if _icon.texture != _start_icon:
		_icon.texture = _start_icon
	if not visible:
		show()

# "You are holding/dragging this" - clenched-hand icon.
func show_hold() -> void:
	if _icon == null:
		return
	if _icon.texture != _hold_icon:
		_icon.texture = _hold_icon
	if not visible:
		show()

# Nothing drag-able in range / not dragging -> remove the cursor entirely.
func hide_cursor() -> void:
	if visible:
		hide()
