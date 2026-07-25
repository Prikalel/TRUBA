extends GridContainer
class_name InventoryGrid

const FIRST_HAND_I = 0
const SECOND_HAND_I = 1
const RADIO_I = 3
const FLASHLIGHT_I = 4
const SECOND_ROW_MIN_I = 5

var slot = preload("res://scenes/ui/inventory_slot.tscn")
# DOWNGRADE NOTE: Godot 3.x has no typed arrays; use a plain Array.
var slots: Array = []

var available_slots_cnt: int = 5

var _flash_texture = load("res://assets/textures/ui/slot_icons/flash.png")
var _transmitter_texture = load("res://assets/textures/ui/slot_icons/transmitter.png")
var _hand_1_texture = load("res://assets/textures/ui/slot_icons/slot_1.png")
var _hand_2_texture = load("res://assets/textures/ui/slot_icons/slot_2.png")

## Устанавливает предмет в ячейку
func set_pickup_in_slot(slot_indx: int, pickup_id: int) -> void:
	slots[slot_indx].current = PickupData.get_by_id(pickup_id)

## Проверяет что для переданного PickupClass существует свободная ячейка
func free_slot_exists(for_class: int) -> int:
	if for_class == PickupClass.WEAPON:
		return _free_slot_exists([FIRST_HAND_I, SECOND_HAND_I], [])
	if for_class == PickupClass.FOOD or for_class == PickupClass.OTHER:
		return _free_slot_exists([], [])
	if for_class == PickupClass.RADIO:
		return _free_slot_exists([], [RADIO_I])
	if for_class == PickupClass.FLASHLIGHT:
		return _free_slot_exists([], [FLASHLIGHT_I])
	push_error("Unknown pickup class " + str(for_class))
	return -1

## include - ячейки в первом ряду для влкючения, only - проверять только эти ячейки
# DOWNGRADE NOTE: typed Array[int] params -> untyped Array params.
func _free_slot_exists(include, only) -> int:
	if only != null and len(only) > 0:
		for i in range(len(slots)):
			if i in only and slots[i].is_empty():
				return i
		return -1
	for i in range(len(slots)):
		if (i in include or i >= SECOND_ROW_MIN_I) and slots[i].is_empty():
			return i
	return -1

func _ready():
	for i in range(15):
		# DOWNGRADE NOTE: instantiate() -> instance().
		var new_slot: InventorySlot = slot.instance() as InventorySlot
		add_child(new_slot)
		slots.append(new_slot)
		if i == FIRST_HAND_I:
			new_slot.set_background(_hand_1_texture)
		elif i == SECOND_HAND_I:
			new_slot.set_background(_hand_2_texture)
		elif i == 2:
			new_slot._blocked = true
			# DOWNGRADE NOTE: Godot 3.x has no Color(base, alpha) ctor and Color.RED
			# is Color.red; build the color manually and set its alpha.
			var _modulate = Color.red
			_modulate.a = 0.0
			new_slot.modulate = _modulate
		elif i == RADIO_I:
			new_slot.set_background(_transmitter_texture)
		elif i == FLASHLIGHT_I:
			new_slot.set_background(_flash_texture)
		elif i >= SECOND_ROW_MIN_I + available_slots_cnt:
			new_slot.blocked = true
