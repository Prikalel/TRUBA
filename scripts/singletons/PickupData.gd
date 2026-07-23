# Хранит и предоставляет информацию о всех предметах

extends Node

# DOWNGRADE NOTE: Godot 3.x has no typed arrays; use plain Array.
var _pickups: Array = []
var _weapons: Array = []

func _ready():
	_load_pickups()
	_load_weapons()

func _load_pickups() -> void:
	_pickups = []
	# DOWNGRADE NOTE: Godot 3.x uses File (not FileAccess): File.new() + open(path, File.READ).
	var file = File.new()
	file.open("res://csv/pickups_registry.csv", File.READ)
	while !file.eof_reached():
		# DOWNGRADE NOTE: PackedStringArray -> PoolStringArray.
		var csv: PoolStringArray = file.get_csv_line()
		if csv.size() == 4:
			# id | класс | иконка | сцена для внешнего мира при выкидывании
			var pickup: PickupObj = PickupObj.new(csv[0], csv[1], csv[2], csv[3])
			_pickups.push_back(pickup)
		else:
			push_error("Incorrect number of columns in pickups_registry.csv: " + str(csv.size()))
	file.close()

func _load_weapons() -> void:
	_weapons = []
	var file = File.new()
	file.open("res://csv/pickups_weapons.csv", File.READ)
	while !file.eof_reached():
		var csv: PoolStringArray = file.get_csv_line()
		if csv.size() == 2:
			# id | сцена для руки
			var weapon: WeaponObj = WeaponObj.new(csv[0], csv[1])
			_weapons.push_back(weapon)
		else:
			push_error("Incorrect number of columns in pickups_weapons.csv: " + str(csv.size()))
	file.close()

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
