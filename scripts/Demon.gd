extends KinematicBody
# Demon.gd - Melee enemy AI: navigates toward the player and attacks when close.
#
# Scope: path-routing (via a Navigation node), animation playback and a
# KinematicBody collision body ONLY. It deliberately contains NO HP / damage /
# "player can shoot the demon" logic.
#
# Two states:
#   WALK   - move toward the player along the nav path; play the walk animation.
#   ATTACK - stop, face the player, play the punch animation, emit `hit` on a
#            cooldown (signal only - no HP deduction here).
#
# Vertical handling: by default `use_gravity` is OFF and the demon is locked to
# its spawn height, moving only on the XZ plane. This is because the level's
# collision floor sits below its visible floor, so gravity made the demon sink.
# The X component of the nav path is used only for horizontal (XZ) steering. If
# the level's floor collision is later fixed to match the visible floor, enable
# `use_gravity` and the demon will settle on it normally.

# Emitted on each melee hit (every attack_cooldown). Nothing damages anything
# here; connect this signal wherever real damage is eventually implemented.
signal hit

# --- Inspector parameters ------------------------------------------------------
# Horizontal movement speed (m/s).
export var move_speed: float = 2.0
# Horizontal distance at which the demon starts attacking.
export var attack_distance: float = 1.6
# Seconds between melee hits while attacking.
export var attack_cooldown: float = 1.0
# How often the nav path is recomputed.
export var path_recalc_interval: float = 0.4
# Smoothing speed for facing direction (higher = snappier).
export var rotation_speed: float = 6.0
# When true the demon falls with gravity; when false (default) it is locked to
# its spawn height and only moves on the XZ plane.
export var use_gravity: bool = false
# Vertical acceleration when use_gravity is enabled (matches the Player).
export var gravity: float = -12.0
# Clamp so the demon never tunnels through floors when gravity is enabled.
export var max_fall_speed: float = 7.0
# Path to the player node (Demon and Player are siblings under the scene root).
export var player_path: NodePath = NodePath("../Player")
# Path to the Navigation node used for path queries.
export var nav_node_path: NodePath = NodePath("../Navigation")
# Animation clip names as imported in Demon.glb (clips are prefixed "Demon|").
export var walk_anim: String = "Demon|Walk1"
export var attack_anim: String = "Demon|Punch1"
# Yaw correction so the model faces its target. The imported Demon model faces
# +Z (opposite Godot's -Z forward), so 180 keeps its front toward the player.
export var model_yaw_offset_deg: float = 180.0

# --- Internal state ------------------------------------------------------------
enum State { WALK, ATTACK }
# -1 = not yet set, so the first _set_state() in _ready actually fires and starts
# the animation (instead of being skipped as "already in that state").
var _state: int = -1

# DOWNGRADE NOTE: Godot 3.x KinematicBody has no built-in velocity member and
# move_and_slide() requires velocity as an argument, so it is stored here.
var _velocity: Vector3 = Vector3.ZERO
var _player: KinematicBody = null
var _nav: Navigation = null
var _anim_player: AnimationPlayer = null

var _path: PoolVector3Array = PoolVector3Array()
var _path_index: int = 0
var _path_timer: float = 0.0
var _attack_timer: float = 0.0
# Spawn height captured in _ready; used to lock vertical position when gravity
# is disabled.
var _spawn_y: float = 0.0

# Distance (XZ) to consider a waypoint reached.
const _WAYPOINT_REACH = 0.6
const _UP = Vector3.UP


func _ready() -> void:
	_spawn_y = global_transform.origin.y

	# Resolve the player node from the exported path; fall back to the "player"
	# group so the script still works if the path is wrong/empty.
	_player = get_node_or_null(player_path) as KinematicBody
	if _player == null:
		for p in get_tree().get_nodes_in_group("player"):
			if p is KinematicBody:
				_player = p as KinematicBody
				break

	# Resolve the Navigation node used for path queries. If the exported path is
	# missing, search the owning scene for one.
	_nav = get_node_or_null(nav_node_path) as Navigation
	if _nav == null and owner != null:
		_nav = _find_first_of_type(owner, "Navigation") as Navigation

	# Find the AnimationPlayer that ships inside the instanced model (the exact
	# node name varies between imports, so search descendants by type).
	_anim_player = _find_first_of_type(self, "AnimationPlayer") as AnimationPlayer
	_ensure_loop(walk_anim)
	_ensure_loop(attack_anim)

	# Start walking toward the player.
	_set_state(State.WALK)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# Vertical handling: either fall with gravity or stay locked to spawn height.
	if use_gravity:
		_velocity.y = clamp(_velocity.y + gravity * delta, -max_fall_speed, max_fall_speed)
	else:
		_velocity.y = 0.0

	# Horizontal (XZ) distance drives the state machine so floor-level differences
	# between the baked navmesh and the real floor don't flip states erratically.
	var distance := _horizontal_distance_to(_player)
	if distance <= attack_distance:
		_set_state(State.ATTACK)
	else:
		_set_state(State.WALK)

	match _state:
		State.WALK:
			_process_walk(delta)
		State.ATTACK:
			_process_attack(delta)

	# DOWNGRADE NOTE: Godot 3.x move_and_slide takes velocity & up direction and
	# returns the resulting velocity (no parameter-less overload exists).
	_velocity = move_and_slide(_velocity, _UP)

	if not use_gravity:
		# Glue the demon to its spawn height so it never sinks through a floor
		# whose collision surface does not match its visible mesh.
		var origin := global_transform.origin
		origin.y = _spawn_y
		global_transform.origin = origin


# --- States --------------------------------------------------------------------

func _process_walk(delta: float) -> void:
	# Recompute the nav path periodically (cheap path queries on a timer).
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = path_recalc_interval
		_recompute_path()

	var target := Vector3.ZERO
	var has_target := false

	# Follow nav waypoints when a path is available. Skip the first point (it is
	# the demon's current position) and advance past any already-reached ones.
	while _path.size() > 1 and _path_index < _path.size():
		var waypoint := _path_to_global(_path[_path_index])
		var to_waypoint := waypoint - global_transform.origin
		to_waypoint.y = 0.0
		if to_waypoint.length() < _WAYPOINT_REACH:
			_path_index += 1
			continue
		target = waypoint
		has_target = true
		break

	# Fall back to a straight line if navigation is unavailable/empty so the
	# demon still approaches the player without a working navmesh.
	if not has_target:
		target = _player.global_transform.origin
		has_target = true

	var to_target := target - global_transform.origin
	to_target.y = 0.0
	if to_target.length() > 0.01:
		var direction := to_target.normalized()
		_velocity.x = direction.x * move_speed
		_velocity.z = direction.z * move_speed
		_face_toward(target, delta)
	else:
		_velocity.x = 0.0
		_velocity.z = 0.0


func _process_attack(delta: float) -> void:
	# Stand still while attacking.
	_velocity.x = 0.0
	_velocity.z = 0.0
	_face_toward(_player.global_transform.origin, delta)

	# Cooldown-gated melee "hit". This only emits a signal (structure); it does
	# NOT deduct any HP - that belongs to a future damage system.
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = attack_cooldown
		emit_signal("hit")


# --- Navigation ----------------------------------------------------------------

# Recompute a path from the demon to the player. The Navigation API works in the
# Navigation node's local space, so positions are converted to/from local. With
# the Navigation node placed at the scene origin (identity) local == global.
func _recompute_path() -> void:
	_path = PoolVector3Array()
	_path_index = 1
	if _nav == null or not is_instance_valid(_player):
		return
	var from := _nav.to_local(global_transform.origin)
	var to := _nav.to_local(_player.global_transform.origin)
	_path = _nav.get_simple_path(from, to, true)


# Converts a nav path point (Navigation-local) back to world space. Falls back to
# the raw value when there is no Navigation node.
func _path_to_global(point: Vector3) -> Vector3:
	if _nav != null:
		return _nav.to_global(point)
	return point


# --- Helpers -------------------------------------------------------------------

func _set_state(new_state: int) -> void:
	if _state == new_state:
		return
	_state = new_state
	match new_state:
		State.WALK:
			_play(walk_anim)
		State.ATTACK:
			_play(attack_anim)
			# Allow the first hit quickly when entering melee range.
			_attack_timer = 0.0


func _play(anim_name: String) -> void:
	if _anim_player == null or not _anim_player.has_animation(anim_name):
		return
	if _anim_player.current_animation != anim_name:
		_anim_player.play(anim_name)


# Defensive: only set loop when the imported animation actually exists.
func _ensure_loop(anim_name: String) -> void:
	if _anim_player == null or not _anim_player.has_animation(anim_name):
		return
	_anim_player.get_animation(anim_name).loop = true


# Smoothly rotates around the Y axis only (no tilting) so the demon faces the
# given world-space position. Uses the -Z forward convention plus the exported
# yaw offset so the model's authored front points at the target.
func _face_toward(target_global: Vector3, delta: float) -> void:
	var to_target := target_global - global_transform.origin
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return
	var target_yaw := atan2(-to_target.x, -to_target.z) + deg2rad(model_yaw_offset_deg)
	var weight: float = clamp(rotation_speed * delta, 0.0, 1.0)
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)


func _horizontal_distance_to(node: Spatial) -> float:
	var offset := node.global_transform.origin - global_transform.origin
	offset.y = 0.0
	return offset.length()


# Depth-first search for the first descendant of `node` matching a class name.
func _find_first_of_type(node: Node, type: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type:
			return child
		var found := _find_first_of_type(child, type)
		if found != null:
			return found
	return null
