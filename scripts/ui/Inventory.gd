extends Control
class_name Inventory

# DOWNGRADE NOTE: Godot 3.x signals are untyped.
signal weapon_in_hand_slot(hand_slot_indx, pickup_id)

# DOWNGRADE NOTE: @onready -> onready.
onready var grid: InventoryGrid = $HBoxContainer/VBoxContainer/TableMargin/GridContainer

## Ищет пикап в области и возвращает true если удалось взять
func find_pickup_in_area(interact_area: Area) -> bool:
	var list = interact_area.get_overlapping_bodies()
	for i in range(len(list)):
		var collision_node = Utils.get_suitable_parent(list[i], PickupBase)
		if collision_node != null:
			if pick_pickup_if_possible(collision_node):
				collision_node.queue_free()
				return true
	return false

func pick_pickup_if_possible(pickup_node: PickupBase) -> bool:
	var pickup_obj: PickupObj = PickupData.get_by_id(pickup_node.pickup_id)
	if pickup_obj == null:
		push_error("Can't find pickup with id " + str(pickup_node.pickup_id))
		return false
	var slot_for_pickup = grid.free_slot_exists(pickup_obj.pickup_class)
	if slot_for_pickup < 0:
		push_warning("Can't pickup item: the inventory is full") # TODO - написать игроку
		return false
	grid.set_pickup_in_slot(slot_for_pickup, pickup_node.pickup_id)
	if ((pickup_obj.pickup_class == PickupClass.WEAPON
		or pickup_obj.pickup_class == PickupClass.FIREARM) and
		(slot_for_pickup == InventoryGrid.FIRST_HAND_I or
		slot_for_pickup == InventoryGrid.SECOND_HAND_I)):
			# DOWNGRADE NOTE: signal.emit(args) -> emit_signal("signal", args).
			emit_signal("weapon_in_hand_slot", slot_for_pickup, pickup_obj.id)
	return true

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	hide()

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.scancode != KEY_W
			and event.scancode != KEY_A
			and event.scancode != KEY_S
			and event.scancode != KEY_D
			and event.scancode != KEY_E
			and event.scancode != KEY_SPACE
			and event.scancode != KEY_CONTROL):
			if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				hide()
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				show()
