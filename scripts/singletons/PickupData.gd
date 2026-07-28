# Хранит и предоставляет информацию о всех предметах

extends Node

# Pickup registry.
#
# The (tiny) tables are embedded directly here so there is zero file I/O (synchronous
# File reads on res:// are not reliable for non-resource text files in the HTML5 export).
#
# pickups columns: id | class | icon | world_scene
const _PICKUP_ROWS := [
	["0", "0", "res://assets/textures/ui/slot_icons/frying_pan.png", "scene_path"],
	["1", "0", "res://assets/textures/T_axe_icon.png", "scene_path"],
	["2", "4", "res://assets/textures/ui/slot_icons/key_icon.png", "scene_path"],
	["3", "5", "res://assets/textures/ui/pistol_icon.png", "scene_path"],
]
# weapons columns: id | hand_scene
const _WEAPON_ROWS := [
	["0", "res://scenes/weapons/pan.tscn"],
	["1", "res://scenes/weapons/axe.tscn"],
]

# DOWNGRADE NOTE: Godot 3.x has no typed arrays; use plain Array.
var _pickups: Array = []
var _weapons: Array = []

func _ready():
	_load_pickups()
	_load_weapons()

func _load_pickups() -> void:
	_pickups = []
	for row in _PICKUP_ROWS:
		if row.size() == 4:
			# id | класс | иконка | сцена для внешнего мира при выкидывании
			var pickup: PickupObj = PickupObj.new(row[0], row[1], row[2], row[3])
			_pickups.push_back(pickup)
		else:
			push_error("Incorrect number of columns in pickup row: " + str(row.size()))

func _load_weapons() -> void:
	_weapons = []
	for row in _WEAPON_ROWS:
		if row.size() == 2:
			# id | сцена для руки
			var weapon: WeaponObj = WeaponObj.new(row[0], row[1])
			_weapons.push_back(weapon)
		else:
			push_error("Incorrect number of columns in weapon row: " + str(row.size()))

## Возвращает основную информацию о поднимаемом предмете по его id
func get_by_id(id: int) -> PickupObj:
	# DOWNGRADE NOTE: Godot 3.x has no Array.map() lambdas and the inline ternary
	# was expanded into a plain loop + early return for clarity/safety.
	var indx: int = -1
	for i in range(len(_pickups)):
		if _pickups[i].id == id:
			indx = i
			break
	if indx < 0:
		return null
	return _pickups[indx]

## Возвращает информацию о оружии по id предмета
func weapon_by_id(id: int) -> WeaponObj:
	var indx: int = -1
	for i in range(len(_weapons)):
		if _weapons[i].id == id:
			indx = i
			break
	if indx < 0:
		return null
	return _weapons[indx]
