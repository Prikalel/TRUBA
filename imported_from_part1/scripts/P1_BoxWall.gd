extends CSGBox

# MIGRATED FROM part1/scripts/BoxWall.gd  (file -> P1_BoxWall.gd). No threading; unchanged logic.

func _ready():
	$StaticBody.directions.clear()
	var rot = $StaticBody.global_rotation.y + PI / 2.0
	if rot > PI:
		rot -= 2 * PI
	$StaticBody.directions = [rot]
