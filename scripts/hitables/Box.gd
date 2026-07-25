extends HittableBase

# Pre-fractured replacement shown when this box is destroyed. Its fragments are
# turned into physics shards by BoxBroken.gd (see scenes/surroundings/box_broken.tscn).
const BROKEN_SCENE := preload("res://scenes/surroundings/box_broken.tscn")

var destroyed: bool = false
export var draggable: bool = true

# Optional contents stored inside the box as a Static RigidBody (e.g. the keys).
# On destruction it is reparented to the box's parent (one level up) and switched
# back to a dynamic RigidBody so it drops exactly where the box stood.
export (NodePath) var keys_node_path := NodePath("RigidBodyKeys")

func _ready():
	# Mark this box as grabbable by the player's drag system (Player.get_is_dragging
	# looks for the "draggable" meta).
	if draggable:
		set_meta("draggable", true)
	# Proximity feedback: a distance-based outline, visible through walls.
	var outline = preload("res://scripts/HighlightOutline.gd").new()
	outline.name = "HighlightOutline"
	add_child(outline)

func get_hit() -> void:
	if destroyed:
		return
	destroyed = true
	# If the box holds a Static RigidBody (e.g. the keys), release it first so it is
	# not freed together with the box: reparent it to this box's parent and enable
	# physics so it drops in place. Must happen before queue_free().
	_release_keys()
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

func _release_keys() -> void:
	var keys = null
	# 1) Prefer the explicitly configured node path (default "RigidBodyKeys").
	if not keys_node_path.is_empty():
		keys = get_node_or_null(keys_node_path)
	# 2) Fallback: any direct child RigidBody currently kept Static (e.g. the keys),
	#    so this also works if the node was named differently in the scene.
	if keys == null:
		for child in get_children():
			if child is RigidBody and child.mode == RigidBody.MODE_STATIC:
				keys = child
				break
	if keys == null:
		return
	# Preserve the same world position/orientation after reparenting one level up.
	var keys_global = keys.global_transform
	var new_parent = get_parent()
	keys.get_parent().remove_child(keys)
	new_parent.add_child(keys)
	keys.global_transform = keys_global
	# Switch from Static back to a dynamic RigidBody and wake it so physics starts.
	keys.mode = RigidBody.MODE_RIGID
	keys.sleeping = false
	keys.visible = true
