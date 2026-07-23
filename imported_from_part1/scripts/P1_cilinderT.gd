extends Spatial

# MIGRATED FROM part1/scripts/cilinderT.gd  (file -> P1_cilinderT.gd). No threading; unchanged logic.

func _ready():
	$StaticBody.directions.clear()
	var rot_1 = $StaticBody.global_rotation.y - PI / 2
	var rot_2 = $StaticBody.global_rotation.y
	var rot_3 = $StaticBody.global_rotation.y - PI
	if rot_1 < -PI:
		rot_1 += 2 * PI
	if rot_3 < -PI:
		rot_3 += 2 * PI
	$StaticBody.directions = [rot_1, rot_2, rot_3]
