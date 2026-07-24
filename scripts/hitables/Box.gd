extends HittableBase

# Pre-fractured replacement shown when this box is destroyed. Its fragments are
# turned into physics shards by BoxBroken.gd (see scenes/surroundings/box_broken.tscn).
const BROKEN_SCENE := preload("res://scenes/surroundings/box_broken.tscn")

var destroyed: bool = false

func _ready():
	# Mark this box as grabbable by the player's drag system (Player.get_is_dragging
	# looks for the "draggable" meta).
	set_meta("draggable", true)

func get_hit() -> void:
	if destroyed:
		return
	destroyed = true
	# Swap the intact box for the pre-fractured one at the same world transform so the
	# shards spawn exactly where the box stood, then free the intact box. (Previously
	# this called $Destruction.Destroy(...) but no such node exists in the scene, which
	# is why the box never broke on a frying-pan hit.)
	var broken = BROKEN_SCENE.instance()
	var parent = get_parent()
	var keep_transform = global_transform
	parent.add_child(broken)
	broken.global_transform = keep_transform
	queue_free()
