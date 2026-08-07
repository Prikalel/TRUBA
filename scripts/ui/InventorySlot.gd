extends Panel
class_name InventorySlot

# Emitted on a left-click while the inventory is open (see _gui_input). The
# InventoryGrid listens and consumes FOOD items (e.g. the looted rat).
signal pressed

# DOWNGRADE NOTE: Godot 3.x uses setget instead of get/set property blocks.
var blocked: bool = false setget _set_blocked, _get_blocked
var current = null setget _set_current, _get_current

var _blocked : bool = false # Доступна игроку
var _current: PickupObj = null  # Предмет, если Null - пустая ячейка

# DOWNGRADE NOTE: @onready -> onready.
onready var background: TextureRect = $BackgroundImg
onready var foreground: TextureRect = $ForegroundImg
onready var _blocked_texture = load("res://assets/textures/ui/slot_icons/none.png")

func _ready() -> void:
	# The icon TextureRects sit on top of the Panel and would otherwise swallow the
	# click (their default mouse_filter is STOP), so make them transparent to the
	# mouse and let the Panel itself receive _gui_input.
	foreground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _gui_input(event) -> void:
	# Only arrives while the inventory (and thus this slot) is actually shown; the
	# whole Control tree is hidden otherwise, so no input is processed when closed.
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		emit_signal("pressed")

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
		return
	# Страховка от перезаписи: никогда молча не затираем уже занятую ячейку другим
	# предметом (иначе предметы стакаются/теряются). Очистка (value == null) и запись в
	# пустую ячейку всегда разрешены, поэтому съедание/сброс предмета продолжает работать.
	# Это последний рубеж: вызывающий код должен брать индекс через free_slot_exists()
	# (только пустые ячейки).
	if value != null and _current != null:
		push_warning("InventorySlot: ячейка уже занята, перезапись отменена")
		return
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
	else:
		# Drop the icon when the item is consumed/removed so the slot reads empty.
		foreground.texture = null

func set_background(new_texture) -> void:
	background.texture = new_texture

# Находится ли в этой ячейке предмет.
func is_empty() -> bool:
	return not blocked and current == null
