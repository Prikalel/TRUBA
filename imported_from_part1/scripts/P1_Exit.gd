extends CSGBox

# MIGRATED FROM part1/scripts/Exit.gd  (file -> P1_Exit.gd).
# No threading / OS.delay in the original — kept behaviour-identical (web-safe).

func _on_StaticBody_area_shape_entered(area_rid, area, area_shape_index, local_shape_index):
	$Label.visible = true
	get_tree().paused = true
