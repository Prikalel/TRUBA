extends Panel
class_name InventorySlot

# DOWNGRADE NOTE: Godot 3.x uses setget instead of get/set property blocks.
var blocked: bool = false setget _set_blocked, _get_blocked
var current = null setget _set_current, _get_current

var _blocked : bool = false # Доступна игроку
var _current: PickupObj = null  # Предмет, если Null - пустая ячейка

# DOWNGRADE NOTE: @onready -> onready.
onready var background: TextureRect = $BackgroundImg
onready var foreground: TextureRect = $ForegroundImg
onready var _blocked_texture = load("res://assets/textures/ui/slot_icons/none.png")

func _get_blocked() -> bool:
	return _blocked

func _set_blocked(value) -> void:
	_blocked = value
	_update_background_if_blocked()

func _get_current():
	return _current

func _set_current(value) -> void:
	if _blocked:
		push_error("Attempt to set pickup in blocked slot!")
	else:
		_current = value
		_update_foreground_with_item()

func _update_background_if_blocked() -> void:
	if _blocked:
		background.texture = _blocked_texture
		# DOWNGRADE NOTE: Godot 3.x has no Color(base, alpha) ctor; copy modulate and set .a.
		var _modulate = self.modulate
		_modulate.a = 0.5
		self.modulate = _modulate
	else:
		background.texture = null
		var _modulate_full = self.modulate
		_modulate_full.a = 1.0
		self.modulate = _modulate_full

func _update_foreground_with_item() -> void:
	if _current != null:
		foreground.texture = load(_current.icon)

func set_background(new_texture) -> void:
	background.texture = new_texture

# Находится ли в этой ячейке предмет.
func is_empty() -> bool:
	return not blocked and current == null
