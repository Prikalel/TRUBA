extends Spatial
# Reusable floating interaction prompt (the "E" letter) that billboards toward the
# player's camera.
#
# This is the Godot-3.x stand-in for the Label3D the original Godot-4 project used:
# it renders a Label into a Viewport and shows that texture on a Sprite3D which is
# manually re-oriented toward the player every frame. PickupBase._process used to do
# exactly this inline; the logic was lifted here so that pickups AND draggable props
# share the exact same prompt.
#
# Attach as a child Spatial of whatever node owns the prompt, then call
# show_prompt()/hide_prompt(). The Sprite3D sits `offset` above this node's origin.

const DEFAULT_OFFSET := Vector3(0, 0.5, 0)
const FONT_PATH := "res://assets/Titillium-Regular.otf"

var floating_text: Sprite3D = null
var _floating_viewport: Viewport = null
var _camera: Spatial = null

func show_prompt(camera_node: Spatial, text: String = "E", offset: Vector3 = DEFAULT_OFFSET, font_size: int = 64) -> void:
	_camera = camera_node
	if floating_text != null:
		# Already visible; keep tracking the (possibly new) camera reference.
		return
	var SIZE := 128
	_floating_viewport = Viewport.new()
	_floating_viewport.size = Vector2(SIZE, SIZE)
	_floating_viewport.transparent_bg = true
	_floating_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	var label := Label.new()
	label.text = text
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.rect_min_size = Vector2(SIZE, SIZE)
	var dynamic_font := DynamicFont.new()
	dynamic_font.font_data = load(FONT_PATH)
	dynamic_font.size = font_size
	label.set("custom_fonts/font", dynamic_font)
	_floating_viewport.add_child(label)
	add_child(_floating_viewport)
	floating_text = Sprite3D.new()
	floating_text.texture = _floating_viewport.get_texture()
	# DOWNGRADE NOTE: Godot 3.x Spatial uses .translation (not .position).
	floating_text.translation = offset
	add_child(floating_text)

func hide_prompt() -> void:
	if floating_text != null:
		remove_child(floating_text)
		floating_text.queue_free()
		floating_text = null
	if _floating_viewport != null:
		remove_child(_floating_viewport)
		_floating_viewport.queue_free()
		_floating_viewport = null
	_camera = null

func _process(_delta: float) -> void:
	if floating_text != null and _camera != null and is_instance_valid(_camera):
		# DOWNGRADE NOTE: Godot 3.x Spatial uses global_transform.origin (not global_position).
		floating_text.look_at(_camera.global_transform.origin, Vector3.UP)
		# DOWNGRADE NOTE: Godot 3 Spatial has no global_rotation (Godot-4-only); global_rotate() is the equivalent.
		floating_text.global_rotate(Vector3.UP, PI)
