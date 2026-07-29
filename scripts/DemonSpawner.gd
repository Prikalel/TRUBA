extends Spatial
class_name DemonSpawner

# Periodically spawns a Demon (assets/prefabs/Demon.tscn) at this marker's world
# position on a random loop. Attach ONE copy of this script to each SPAWNPOINT
# node (SPAWNPOINT1, SPAWNPOINT2, ...); every marker runs its own independent
# countdown.
#
# IMPORTANT: the Demon is added as a child of the SCENE ROOT (this node's parent),
# NOT under the spawnpoint. Demon.gd resolves its target & navigation through the
# NodePaths "../Player" and "../Navigation", which only resolve while the demon is
# a direct child of the scene root. The spawnpoint only supplies the spawn
# position via its global transform.

# Demon prefab to instance on each spawn.
export var demon_scene: PackedScene = preload("res://assets/prefabs/Demon.tscn")
# Min/max seconds (inclusive) between spawns. A fresh random value is rolled after
# every spawn, including the very first one scheduled in _ready.
export var min_interval: float = 5.0
export var max_interval: float = 30.0

# Seconds left until the next spawn.
var _timer: float = 0.0


func _ready() -> void:
	# The first spawn also waits a random 5-30s (same rule as every later spawn).
	_timer = _random_interval()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_spawn_demon()
		_timer = _random_interval()


# Returns a random float in [min_interval, max_interval].
func _random_interval() -> float:
	return rand_range(min_interval, max_interval)


func _spawn_demon() -> void:
	if demon_scene == null:
		push_error("DemonSpawner has no demon_scene assigned")
		return
	# Parented to the scene root so the demon's "../Player" / "../Navigation"
	# NodePaths resolve (see Demon.gd). Order matters: add_child first, THEN set
	# the global transform (Godot warns if global_transform is set off-tree).
	var root: Node = get_parent()
	var demon: Spatial = demon_scene.instance() as Spatial
	root.add_child(demon)
	demon.global_transform = global_transform
	# Set owner to the scene root so Demon.gd's owner-based Navigation fallback
	# (see _find_first_of_type(owner, ..)) can still search the whole scene.
	demon.owner = root
