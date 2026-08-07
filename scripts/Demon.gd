extends KinematicBody
# Demon.gd - Melee enemy AI: navigates toward the player and attacks when close.
#
# Scope: path-routing (via a Navigation node), animation playback and a
# KinematicBody collision body. The ATTACK state damages the player: each punch
# removes 1 heart via Player.take_damage() when it connects. The Demon itself
# still has NO HP and cannot be shot yet.
#
# Two states:
#   WALK   - move toward the player along the nav path; play the walk animation.
#   ATTACK - stop, face the player, play the punch animation; the attack
#            animation's method-call tracks invoke _process_punch() at the frames
#            where the blow lands, dealing damage if the player is still in range.
#
# Vertical handling: by default `use_gravity` is OFF and the demon is locked to
# its spawn height, moving only on the XZ plane. This is because the level's
# collision floor sits below its visible floor, so gravity made the demon sink.
# The X component of the nav path is used only for horizontal (XZ) steering. If
# the level's floor collision is later fixed to match the visible floor, enable
# `use_gravity` and the demon will settle on it normally.

# Informational: emitted on the attack cooldown (see _process_attack). Actual
# damage is dealt from _process_punch(), driven by the attack animation's
# method-call tracks, so this signal is currently unused / purely optional.
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
export var attack_anim: String = "animsDemon_Punch1_with_method_call"
# Yaw correction so the model faces its target. The imported Demon model faces
# +Z (opposite Godot's -Z forward), so 180 keeps its front toward the player.
export var model_yaw_offset_deg: float = 180.0

# --- Health & death ------------------------------------------------------------
# Demon HP (1 by default, so a single raycast shot kills it).
export var max_health: int = 1
# Death animation clip name (imported in Demon.glb, prefixed "Demon|").
export var death_anim: String = "Demon|Death"
# Seconds the corpse is left on the ground before the whole demon node is freed.
export var corpse_despawn_delay: float = 15.0

# --- Walking ambience ----------------------------------------------------------
# Min/max seconds of silence between two random footstep-style growls while the
# demon is walking.
export var walk_sound_min_interval: float = 7.0
export var walk_sound_max_interval: float = 15.0

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
# Walk/death audio streams and the capsule, resolved in _ready from named nodes
# (WalkStream / DeadStream / CollisionShape) added under the Demon node.
var _walk_stream: AudioStreamPlayer3D = null
var _dead_stream: AudioStreamPlayer3D = null
var _collision_shape: CollisionShape = null

var _path: PoolVector3Array = PoolVector3Array()
var _path_index: int = 0
var _path_timer: float = 0.0
var _attack_timer: float = 0.0
# Spawn height captured in _ready; used to lock vertical position when gravity
# is disabled.
var _spawn_y: float = 0.0
# Current HP (initialised to max_health in _ready).
var _health: int = 1
# Latched once killed: the demon freezes, stops making noise and is despawned later.
var _dead: bool = false
# Counts down from corpse_despawn_delay after death; frees the node when it hits 0.
var _death_timer: float = 0.0
# Walk-growl countdown; when it hits 0 a random demonX.ogg plays and it resets.
var _walk_sound_timer: float = 0.0
# Melee-contact latch: once the demon physically reaches the player (its origin
# cannot get closer because collision keeps the two centres apart), it is treated
# as "in range" until the player leaves the melee band. See _physics_process.
var _in_melee_contact: bool = false

# Distance (XZ) to consider a waypoint reached.
const _WAYPOINT_REACH = 0.6
# Extra distance (beyond attack_distance) within which a collision-blocked demon
# still counts as having reached the player (covers the demon + player collision
# footprints that keep their centres apart).
const _MELEE_CONTACT_MARGIN: float = 1.5
const _UP = Vector3.UP
# Random pool of growl sounds played periodically while walking (see WalkStream).
const _WALK_SOUNDS := [
	preload("res://assets/sounds/demon/walk/demon1.ogg"),
	preload("res://assets/sounds/demon/walk/demon2.ogg"),
	preload("res://assets/sounds/demon/walk/demon3.ogg"),
	preload("res://assets/sounds/demon/walk/demon4.ogg"),
	preload("res://assets/sounds/demon/walk/demon5.ogg"),
]


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

	# Resolve the walk/death audio streams and the capsule (named nodes in test.tscn).
	_walk_stream = get_node_or_null("WalkStream") as AudioStreamPlayer3D
	_dead_stream = get_node_or_null("DeadStream") as AudioStreamPlayer3D
	_collision_shape = get_node_or_null("CollisionShape") as CollisionShape

	# Health & death state: the demon starts at full HP and is shootable.
	_health = max_health
	add_to_group("demon")
	# Stagger the first growl so multiple demons don't all groan on the same frame.
	_walk_sound_timer = rand_range(walk_sound_min_interval, walk_sound_max_interval)

	# Start walking toward the player.
	_set_state(State.WALK)


func _physics_process(delta: float) -> void:
	if _dead:
		# Corpse: hold the death pose and count down to despawn, then free the
		# whole demon node (model + streams + capsule) from the scene.
		_death_timer -= delta
		if _death_timer <= 0.0:
			queue_free()
		return

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

	# "In range" = centre within attack_distance OR already in melee contact (latch
	# below). Centre-to-centre distance alone never triggers when the demon's
	# (scaled) capsule and the player's capsule physically keep the two origins
	# farther apart than attack_distance, so without the contact latch the demon
	# presses against the player and walks in place forever.
	if distance <= attack_distance or _in_melee_contact:
		_set_state(State.ATTACK)
	else:
		_set_state(State.WALK)

	# XZ position before this tick's movement (used to detect a blocked approach).
	var pre_move_xz := Vector2(global_transform.origin.x, global_transform.origin.z)

	match _state:
		State.WALK:
			_process_walk(delta)
		State.ATTACK:
			_process_attack(delta)

	# Horizontal velocity the state handler asked for this tick (pre-collision).
	var attempted_xz := Vector2(_velocity.x, _velocity.z)

	# DOWNGRADE NOTE: Godot 3.x move_and_slide takes velocity & up direction and
	# returns the resulting velocity (no parameter-less overload exists).
	_velocity = move_and_slide(_velocity, _UP)

	# Melee-contact latch. The demon wanted to move toward the player but its body
	# made essentially no horizontal progress => collision is stopping it from
	# getting any closer, i.e. it has physically reached the player. Only latch
	# while pressing TOWARD the player and within the melee band; release once the
	# player clearly leaves the band. It is sticky on purpose so that ATTACK (which
	# zeroes the velocity) does not flip the demon back to WALK every other frame.
	var melee_band := attack_distance + _MELEE_CONTACT_MARGIN
	if not _in_melee_contact:
		var post_move_xz := Vector2(global_transform.origin.x, global_transform.origin.z)
		var horizontal_progress := (post_move_xz - pre_move_xz).length()
		if attempted_xz.length() > 0.5 and horizontal_progress < 0.0005 and distance <= melee_band:
			var to_player_xz := Vector2(
				_player.global_transform.origin.x - pre_move_xz.x,
				_player.global_transform.origin.z - pre_move_xz.y)
			if to_player_xz.length() > 0.001 and attempted_xz.dot(to_player_xz.normalized()) > 0.0:
				_in_melee_contact = true
	elif distance > melee_band:
		_in_melee_contact = false

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

	# Periodic random growl while walking: after each growl, wait a random
	# walk_sound_min_interval..walk_sound_max_interval seconds of silence.
	_walk_sound_timer -= delta
	if _walk_sound_timer <= 0.0:
		_play_random_walk_sound()
		_walk_sound_timer = rand_range(walk_sound_min_interval, walk_sound_max_interval)

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

func _process_punch() -> void:
	# Dead demons never attack (guard against a stray method-call track frame).
	if _dead:
		return
	# Called by method-call tracks on the attack animation timeline at the frames
	# where the punch connects. Plays the attack sound and, if the player is still
	# within attack_distance at that exact moment, removes 1 heart.
	$AudioStreamPlayer3D.play()
	if is_instance_valid(_player) and _player.has_method("take_damage"):
		# "Within range" includes the melee-contact latch: collision can keep the
		# player's centre outside the plain attack_distance even while the bodies
		# are physically touching (see _physics_process). Without this the demon
		# would play the attack animation but never connect.
		if _horizontal_distance_to(_player) <= attack_distance or _in_melee_contact:
			_player.take_damage(1)

# --- Damage & death -------------------------------------------------------------

# Public: the player's hitscan ray calls this when a shot connects (see
# Player.gd _fire_hitscan). With the default 1 HP a single shot kills the demon.
func take_damage(amount: int = 1) -> void:
	if _dead or amount <= 0:
		return
	_health = max(0, _health - amount)
	if _health <= 0:
		_die()


# Plays the death growl + one-shot death animation, freezes the demon in place,
# disables its collision (so the corpse can't be shot again or block the player),
# and starts the despawn countdown handled in _physics_process.
func _die() -> void:
	if _dead:
		return
	_dead = true
	_state = -1
	# Freeze: stop all horizontal movement immediately.
	_velocity.x = 0.0
	_velocity.z = 0.0
	# Stop any looping walk growl; the death growl replaces it.
	if _walk_stream != null:
		_walk_stream.stop()
	# Remove the capsule so the corpse no longer collides with anything.
	if _collision_shape != null:
		_collision_shape.disabled = true
	# Death growl.
	if _dead_stream != null:
		_dead_stream.play()
	# One-shot death pose (never loops); the model stays on its final frame.
	_play_death()
	_death_timer = corpse_despawn_delay


func _play_death() -> void:
	if _anim_player == null or not _anim_player.has_animation(death_anim):
		# No death clip available: just halt whatever is playing.
		if _anim_player != null:
			_anim_player.stop()
		return
	var anim := _anim_player.get_animation(death_anim)
	anim.loop = false
	_anim_player.stop()
	_anim_player.play(death_anim)


func _play_random_walk_sound() -> void:
	if _walk_stream == null or _WALK_SOUNDS.empty():
		return
	var idx := randi() % _WALK_SOUNDS.size()
	_walk_stream.stream = _WALK_SOUNDS[idx]
	_walk_stream.play()

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
