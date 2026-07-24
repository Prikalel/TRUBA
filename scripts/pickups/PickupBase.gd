extends Spatial
class_name PickupBase

## Идентификатор поднимаемого предмета.
# DOWNGRADE NOTE: @export -> export.
export var pickup_id: int = -1

# Floating "E" prompt. The actual rendering lives in FloatingPrompt.gd (shared with
# Draggable props) so pickups and draggable objects display the exact same prompt.
# DOWNGRADE NOTE: Godot 3.x has no Label3D, so the prompt is a Sprite3D fed by a
# Viewport (see FloatingPrompt.gd) and re-oriented toward the player each frame.
var _prompt = null

## Показать подсказку
func show_text(player_node):
	_ensure_prompt()
	_prompt.show_prompt(player_node)

## Скрыть подсказку
func hide_text():
	if _prompt != null:
		_prompt.hide_prompt()

func _ensure_prompt():
	if _prompt == null:
		# preload (not load) so FloatingPrompt is parsed at scene load, not lazily.
		_prompt = preload("res://scripts/FloatingPrompt.gd").new()
		_prompt.name = "FloatingPrompt"
		add_child(_prompt)
