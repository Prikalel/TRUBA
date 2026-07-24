extends Spatial
class_name PickupBase

## Идентификатор поднимаемого предмета.
# DOWNGRADE NOTE: @export -> export.
export var pickup_id: int = -1

var camera: Spatial
# DOWNGRADE NOTE: Godot 3.x has no Label3D. The floating "E" prompt is approximated
# by rendering a Label into a Viewport and showing that texture on a Sprite3D that
# is manually oriented toward the player (same look_at logic the Label3D used).
var floating_text: Sprite3D
var _floating_viewport: Viewport

## Показать подсказку
func show_text(player_node):
	var SIZE_X = 128
	var SIZE_Y = 128
	if (floating_text == null):
		camera = player_node
		_floating_viewport = Viewport.new()
		_floating_viewport.size = Vector2(SIZE_X, SIZE_Y)
		_floating_viewport.transparent_bg = true
		_floating_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
		var label = Label.new()
		label.text = "E"
		label.align = Label.ALIGN_CENTER
		label.valign = Label.VALIGN_CENTER
		label.rect_min_size = Vector2(SIZE_X, SIZE_Y)
		var dynamic_font = DynamicFont.new()
		dynamic_font.font_data = load("res://assets/Titillium-Regular.otf") 
		# 3. Устанавливаем нужный размер (например, 32 пикселя)
		dynamic_font.size = 64 
		# 4. Применяем измененный шрифт к элементу Label
		label.set("custom_fonts/font", dynamic_font)
		_floating_viewport.add_child(label)
		add_child(_floating_viewport)
		floating_text = Sprite3D.new()
		floating_text.texture = _floating_viewport.get_texture()
		# DOWNGRADE NOTE: Godot 3.x Spatial uses .translation (not .position).
		floating_text.translation = Vector3(0, 0.5, 0)
		add_child(floating_text)

## Скрыть подсказку
func hide_text():
	if (floating_text != null):
		remove_child(floating_text)
		floating_text.queue_free()
		floating_text = null
	if (_floating_viewport != null):
		remove_child(_floating_viewport)
		_floating_viewport.queue_free()
		_floating_viewport = null

func _process(_delta):
	if (floating_text != null):
		# DOWNGRADE NOTE: Godot 3.x Spatial uses global_transform.origin (not global_position).
		floating_text.look_at(camera.global_transform.origin, Vector3.UP)
		# DOWNGRADE NOTE: Godot 3 Spatial has no global_rotation (Godot-4-only); global_rotate() is the equivalent.
		floating_text.global_rotate(Vector3.UP, PI)
