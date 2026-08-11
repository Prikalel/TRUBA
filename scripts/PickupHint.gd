extends Control
# Bottom-left screen hint shown while a pickup is in interaction range.
#
# The floating 3D "E" (FloatingPrompt) is generic - it tells the player they can
# interact, but not WHAT they are about to pick up. This 2D hint sits in the
# lower-left corner of the viewport and reads "нажмите E чтобы подобрать (имя)"
# next to the item's icon, so the player sees exactly which item is in range.
#
# Driven by Player._update_pickup_hint, which calls show_hint(pickup_obj) every
# physics frame while a lootable PickupBase overlaps the DragArea, and hide_hint()
# otherwise (and while the inventory/pause menu is open or while dragging).
#
# Pure decoration: MOUSE_FILTER_IGNORE, never consumes input. Attached as a child
# of the Player KinematicBody (a Control under a 3D node renders on the viewport
# canvas, exactly like InteractionCursor and the hearts HUD).

const FONT_PATH := "res://assets/fonts/bookxel-font-2x.tres"
# Pixel inset of the hint box from the bottom-left corner of the screen.
const MARGIN := 24
# Square size (px) of the item icon drawn left of the text.
const ICON_SIZE := 64
# Inner padding between the panel border and its icon/text.
const PADDING := 12
# Horizontal gap between the icon and the text.
const GAP := 12

var _font: DynamicFont = null
var _panel: Panel = null
var _icon: TextureRect = null
var _label: Label = null
# Last icon path currently shown, so the texture is only reloaded on change
# (load() every frame for the same pickup would be wasteful).
var _icon_path: String = ""
# Whether the icon slot is currently shown. False for text-only messages
# (e.g. the "зажмите E и двигайтесь на WASD" drag hint), so _layout() drops the
# icon's reserved width and the box hugs just the text.
var _icon_visible: bool = true

func _ready() -> void:
	# Decorative overlay: never swallow clicks/keys from the game.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Fill the whole viewport so the panel can be anchored to the bottom-left
	# (a Control parented under a 3D node anchors to the root window, same as
	# InteractionCursor / the hearts HUD).
	anchor_right = 1.0
	anchor_bottom = 1.0
	margin_left = 0
	margin_top = 0
	margin_right = 0
	margin_bottom = 0

	_font = load(FONT_PATH)

	_panel = Panel.new()
	_panel.name = "PickupHintPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Dark, slightly translucent rounded rectangle ("небольшой прямоугольник").
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.05, 0.78)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.85, 0.85, 0.85, 0.55)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_panel.add_stylebox_override("panel", style)
	add_child(_panel)

	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.expand = true
	# Keep the source icon's aspect ratio inside the ICON_SIZE box (icons have
	# different native resolutions, e.g. the axe vs the frying pan).
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.rect_min_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_icon)

	_label = Label.new()
	_label.name = "Text"
	_label.align = Label.ALIGN_LEFT
	_label.valign = Label.VALIGN_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_font_override("font", _font)
	_label.add_color_override("font_color", Color(1, 1, 1, 1))
	_panel.add_child(_label)

	# Hidden until a pickup actually enters interaction range.
	hide()

# Show the hint for a given PickupObj (a PickupData registry entry). Cheap to call
# every frame: the text and the icon texture are only (re)set when they change,
# and _layout() re-measures only when the text actually differs.
func show_hint(pickup_obj: PickupObj) -> void:
	if pickup_obj == null:
		hide_hint()
		return
	# Pickup mode always shows the icon (re-enable it after a text-only message).
	_icon_visible = true
	_icon.visible = true
	# Explicit String type: pickup_obj is now typed (PickupObj), but keep the
	# annotation so the inference is unambiguous on every Godot 3.x build.
	var text: String = "нажмите E чтобы подобрать " + pickup_obj.display_name
	if _label.text != text:
		_label.text = text
	if _icon_path != pickup_obj.icon:
		_icon_path = pickup_obj.icon
		_icon.texture = load(pickup_obj.icon)
	_layout()
	if not visible:
		show()

# Text-only message in the same bottom-left box (no icon). Used for the
# "зажмите E и двигайтесь на WASD" hint shown while a drag-able prop is in range
# or is being carried (see Player._update_pickup_hint).
func show_message(text: String) -> void:
	_icon_visible = false
	_icon.visible = false
	if _label.text != text:
		_label.text = text
	_layout()
	if not visible:
		show()

func hide_hint() -> void:
	if visible:
		hide()

# Measures the current text with the loaded font and positions/sizes the panel +
# its children so the box hugs its content and sits in the bottom-left corner.
# Children are positioned manually (no MarginContainer) because in Godot 3.x a
# Panel does not auto-shrink to its children - we drive its size from the text.
func _layout() -> void:
	var screen: Vector2 = rect_size
	if screen.x <= 0 or screen.y <= 0:
		screen = get_viewport_rect().size
	var text_size: Vector2 = _font.get_string_size(_label.text)
	# The icon slot is only reserved in pickup mode; text-only messages (the drag
	# hint) skip the icon + its gap so the box hugs just the text.
	var content_w: float
	var content_h: float
	if _icon_visible:
		content_w = ICON_SIZE + GAP + ceil(text_size.x)
		content_h = max(ICON_SIZE, ceil(text_size.y))
	else:
		content_w = ceil(text_size.x)
		content_h = ceil(text_size.y)
	var panel_w: float = PADDING + content_w + PADDING
	var panel_h: float = PADDING + content_h + PADDING
	# Pin the panel to top-left anchoring and place it manually so the exact
	# measured size holds (anchors would otherwise stretch it).
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.rect_size = Vector2(panel_w, panel_h)
	_panel.rect_position = Vector2(MARGIN, screen.y - panel_h - MARGIN)
	if _icon_visible:
		# Icon: vertically centered on the left, inside the padding.
		_icon.rect_position = Vector2(PADDING, PADDING + (content_h - ICON_SIZE) * 0.5)
		_icon.rect_size = Vector2(ICON_SIZE, ICON_SIZE)
		# Label fills the remaining width, text vertically centered (valign CENTER).
		_label.rect_position = Vector2(PADDING + ICON_SIZE + GAP, PADDING)
		_label.rect_size = Vector2(content_w - ICON_SIZE - GAP, content_h)
	else:
		# Label fills the whole content area (no icon).
		_label.rect_position = Vector2(PADDING, PADDING)
		_label.rect_size = Vector2(content_w, content_h)
