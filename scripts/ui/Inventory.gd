extends Control
class_name Inventory

# DOWNGRADE NOTE: Godot 3.x signals are untyped.
signal weapon_in_hand_slot(hand_slot_indx, pickup_id)
# Emitted when a FOOD item is consumed from the inventory. The Player connects to
# heal 1 HP and play the eating sound.
signal food_consumed

# DOWNGRADE NOTE: @onready -> onready.
onready var grid: InventoryGrid = $HBoxContainer/VBoxContainer/TableMargin/GridContainer

# Controls help text shown on the right side of the pause menu. Russian is the
# default; the 🔣 button (NotoEmoji) swaps to the English translation and back.
onready var controls_label: Label = $HBoxContainer/VBoxContainer2/Label
var _controls_en := false
const CONTROLS_RU := "WASD - перемещение\nМышка - поворот камерой\nЕ - поднять предмет/тащить\nПробел - прыжок, c - присесть\nЛКМ - удар ближний бой\nПКМ - выстрел"
const CONTROLS_EN := "WASD - movement\nMouse - rotate camera\nE - pick up/interact/drag\nSpace - jump, c - crouch\nLMB - melee atack\nRMB - shoot"

## Ищет пикап в области и возвращает true если удалось взять
func find_pickup_in_area(interact_area: Area) -> bool:
	var list = interact_area.get_overlapping_bodies()
	for i in range(len(list)):
		var collision_node = Utils.get_suitable_parent(list[i], PickupBase)
		# can_be_picked_up() gates pickup behind a condition (e.g. the Rat is only
		# lootable once killed); defaults to true for ordinary world pickups.
		if collision_node != null and collision_node.can_be_picked_up():
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
	# Re-broadcast the grid's consumption signal up to the Player.
	grid.connect("food_consumed", self, "emit_signal", ["food_consumed"])
	# "В меню" button: return to the first level (test2.tscn). MainMenu._ready()
	# runs on scene load and re-opens the start menu automatically.
	var to_menu_btn = get_node_or_null("Button_ToMenu")
	if to_menu_btn != null:
		to_menu_btn.connect("pressed", self, "_on_to_menu_pressed")
	# Controls help text starts in Russian (the English duplicate lines were
	# removed from the scene). The 🔣 button toggles between RU and EN.
	controls_label.text = CONTROLS_RU
	var lang_btn = get_node_or_null("HBoxContainer/VBoxContainer2/Button_LangToggle")
	if lang_btn != null:
		lang_btn.connect("pressed", self, "_on_lang_toggle_pressed")

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.scancode != KEY_W
			and event.scancode != KEY_A
			and event.scancode != KEY_S
			and event.scancode != KEY_D
			and event.scancode != KEY_E
			and event.scancode != KEY_SPACE
			and event.scancode != KEY_C):
			if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				hide()
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				show()

# Returns to the first level. MainMenu._ready() runs on load, so the start menu
# is shown again automatically.
func _on_to_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene("res://scenes/test2.tscn")


# 🔣 button in the pause menu: swap the controls help text between Russian
# (default) and English. First press -> English, second press -> Russian, etc.
func _on_lang_toggle_pressed() -> void:
	_controls_en = not _controls_en
	controls_label.text = CONTROLS_EN if _controls_en else CONTROLS_RU
