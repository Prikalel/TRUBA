extends KinematicBody

const GRAVITY = -12
const MAX_SPEED = 3
const MAX_SPEED_CRAWLING = 1.5
export var JUMP_SPEED = 3
const CRAWL_ACCEL_MULTIPLIER = 3
const ACCEL = 4.5
const DEACCEL = 16
const MAX_SLOPE_ANGLE = 40
const MAX_FALLING_SPEED = 7
const HTARGET_WHILE_FALLING_DEACCEL = 3
# Maximum look-up / look-down angle (in degrees) away from the neutral horizon.
const PITCH_LIMIT = 70

# DOWNGRADE NOTE: Godot 3.x KinematicBody has no built-in velocity member and
# move_and_slide() requires velocity as an argument, so it is stored here.
var velocity: Vector3 = Vector3.ZERO
# DOWNGRADE NOTE: Godot 3.x KinematicBody has no floor_max_angle property; it is
# passed straight into move_and_slide() instead.
var floor_max_angle: float = deg2rad(MAX_SLOPE_ANGLE)

var dir: Vector3 = Vector3()
var last_htarget: Vector3 = Vector3()
var is_dragging: bool = false
# Current pitch offset (degrees) from the helper's neutral rotation.
# 0 == looking straight at the horizon; clamped to +/- PITCH_LIMIT.
var pitch: float = 0.0
# Rotation_Helper has a -90deg X rotation baked into the scene so it stays
# upright in world space (parent Body_CollisionShape has a compensating +90deg).
# We cache that baked neutral and drive pitch on top of it, instead of clamping
# the node's raw rotation_degrees (which is offset by ~-90 at the horizon).
var _base_pitch_deg: float = 0.0

var camera: Camera
var rotation_helper: Spatial
var player_capsule: Capsule
var arm: Arm
var drag_area: Area
var inventory: Inventory
# Center-screen interaction cursor for drag-able props (see InteractionCursor.gd).
# Shown when a draggable is in range ("you can grab") or while it is carried.
var interaction_cursor: Control = null

var current_dragging_object: CollisionObject = null
# Saved collision layer/mask (and RigidBody mode) of the object currently being
# carried, restored when it is dropped (see _disable/_restore_drag_collision).
var _drag_original_layer: int = 1
var _drag_original_mask: int = 1
var _drag_original_mode: int = -1
# Prompt owners (pickups / draggable props) for which the floating "E" is currently
# shown. Tracked here because Area.body_entered does not reliably fire for a
# StaticBody (the draggable cube), so prompts are driven by polling instead.
var _prompted: Dictionary = {}
# One-frame bridge: when E is released while carrying, the carried object's
# collision is restored this same frame, but Area.get_overlapping_bodies() only
# reports it on the next physics tick. Without this flag the center cursor would
# blink hidden for one frame on release before showing the open-hand "you can
# grab" icon again.
var _drag_just_released: bool = false

var mouse_sensitivity: float = 0.05

func _ready():
	camera = $Body_CollisionShape/Rotation_Helper/Camera
	rotation_helper = $Body_CollisionShape/Rotation_Helper
	_base_pitch_deg = rotation_helper.rotation_degrees.x
	player_capsule = $Body_CollisionShape as Capsule
	arm = $Body_CollisionShape/Rotation_Helper/Arm as Arm
	drag_area = $Body_CollisionShape/DragArea as Area
	inventory = $Inventory as Inventory
	interaction_cursor = $InteractionCursor as Control
	arm.listen_weapon_change(inventory)
	# So HighlightOutline (and other scripts) can find the player without a hard-coded
	# node path (which varies between scenes) and without any file I/O.
	add_to_group("player")

func _player_not_in_inventory() -> bool:
	return not inventory.visible

func _physics_process(delta):
	if _player_not_in_inventory():
		process_input()
		_update_prompts()
	# Runs every frame (even with the inventory open) so the cursor is removed the
	# instant the menu appears instead of lingering on screen.
	_update_cursor()
	process_movement(delta)
	arm.shake(velocity)

func process_input() -> void:
	var cam_xform = camera.get_global_transform()

	is_dragging = get_is_dragging()

	if is_on_floor():
		dir = Vector3()
		var input_movement_vector: Vector2 = Vector2()
		if Input.is_action_pressed("movement_forward"):
			input_movement_vector.y += 1
		if Input.is_action_pressed("movement_backward"):
			input_movement_vector.y -= 1
		if Input.is_action_pressed("movement_left"):
			input_movement_vector.x -= 1
		if Input.is_action_pressed("movement_right"):
			input_movement_vector.x += 1
		input_movement_vector = input_movement_vector.normalized()

		if Input.is_action_just_pressed("movement_jump"):
			velocity.y = JUMP_SPEED
			player_capsule.disable_crawling()
		elif Input.is_action_just_pressed("movement_crawl"):
			player_capsule.toggle_crawling()

		dir += -cam_xform.basis.z * input_movement_vector.y
		dir += cam_xform.basis.x * input_movement_vector.x
		dir.y = 0
		dir = dir.normalized()
		$AudioStreamPlayer2D.stream_paused = not is_on_floor() or Utils.floats_equal(dir.length(), 0)
	else:
		is_dragging = false

	if not is_dragging and Input.is_action_just_pressed("interaction"):
		if inventory.find_pickup_in_area(drag_area):
			$PlayPickupTaken.play()

func process_movement(delta):
	var hvel = _get_horisontal_velocity(delta)
	velocity.x = hvel.x
	velocity.z = hvel.z

	velocity.y = clamp(velocity.y + delta * GRAVITY, -MAX_FALLING_SPEED, MAX_FALLING_SPEED)

	# DOWNGRADE NOTE: Godot 3.x move_and_slide takes velocity & up direction and
	# returns the resulting velocity (no parameter-less overload exists).
	velocity = move_and_slide(velocity, Vector3.UP, false, 4, floor_max_angle)

func _get_horisontal_velocity(delta: float) -> Vector3:
	var hvel = velocity
	hvel.y = 0

	var htarget
	if is_on_floor():
		var current_speed = MAX_SPEED if not player_capsule.get_crawling() else MAX_SPEED_CRAWLING
		htarget = dir * current_speed
	else:
		# DOWNGRADE NOTE: Godot 3.x Vector3 has no .lerp(); use linear_interpolate.
		htarget = last_htarget.linear_interpolate(Vector3.ZERO, HTARGET_WHILE_FALLING_DEACCEL * delta)
	self.last_htarget = htarget

	var accel
	if dir.dot(hvel) >= 0:
		accel = ACCEL
	else:
		accel = DEACCEL
	if player_capsule.get_crawling():
		accel *= CRAWL_ACCEL_MULTIPLIER

	return hvel.linear_interpolate(htarget, accel * delta)

func get_is_dragging() -> bool:
	if not Input.is_action_pressed("interaction") or player_capsule.get_crawling():
		if (current_dragging_object != null):
			_reparent_keep_global(current_dragging_object, owner)
			_restore_drag_collision(current_dragging_object)
			# Signal a one-frame "just dropped" bridge so the interaction cursor
			# keeps showing the open-hand icon instead of blinking out on key
			# release (crawling still forbids dragging, so don't prompt then).
			if not player_capsule.get_crawling():
				_drag_just_released = true
			current_dragging_object = null
		return false
	if (current_dragging_object == null):
		var list = drag_area.get_overlapping_bodies()
		for i in range(len(list)):
			var collision_node = (list[i] as CollisionObject)
			if collision_node != null and collision_node.has_meta("draggable"):
				var is_draggable_object: bool = collision_node.get_meta("draggable")
				if is_draggable_object:
					current_dragging_object = collision_node
					# Disable collision BEFORE reparenting so the carried object can't
					# block the player (otherwise walking into it gets you stuck).
					_disable_drag_collision(current_dragging_object)
					_reparent_keep_global(current_dragging_object, self)
					break
	return current_dragging_object != null

# While an object is carried it is parented to the player; if it kept its collision
# the player would collide with the very thing they are holding and get stuck. So we
# zero its collision layer/mask while carried and restore the originals on drop. A
# carried RigidBody is also switched to MODE_STATIC so it stops simulating (it would
# otherwise fall through the now-collisionless world instead of following the player).
func _disable_drag_collision(body: CollisionObject) -> void:
	_drag_original_layer = body.collision_layer
	_drag_original_mask = body.collision_mask
	body.collision_layer = 0
	body.collision_mask = 0
	if body is RigidBody:
		var rb = body as RigidBody
		_drag_original_mode = rb.mode
		rb.mode = RigidBody.MODE_STATIC

func _restore_drag_collision(body: CollisionObject) -> void:
	body.collision_layer = _drag_original_layer
	body.collision_mask = _drag_original_mask
	if body is RigidBody and _drag_original_mode >= 0:
		var rb = body as RigidBody
		rb.mode = _drag_original_mode
	_drag_original_mode = -1

# Drives the floating "E" prompt by polling the DragArea every physics frame instead
# of relying solely on Area.body_entered (which does not reliably fire for a
# StaticBody such as the draggable cube). Shows the prompt for every interactable
# currently overlapping the area and hides it for those that left.
func _update_prompts() -> void:
	if is_dragging:
		for owner in _prompted.keys():
			if is_instance_valid(owner):
				owner.hide_text()
		_prompted.clear()
		return
	var still_overlapping: Dictionary = {}
	for body in drag_area.get_overlapping_bodies():
		var owner = _get_prompt_owner(body)
		if owner == null:
			continue
		still_overlapping[owner] = true
		if not _prompted.has(owner):
			owner.show_text(self)
			_prompted[owner] = true
	for owner in _prompted.keys():
		if not still_overlapping.has(owner):
			if is_instance_valid(owner):
				owner.hide_text()
			_prompted.erase(owner)

# Returns true when ANY body currently overlapping the DragArea is flagged as
# drag-able (meta "draggable" == true). This is the "player is looking at
# something they can grab" condition, independent of whether E is held. While an
# object is carried its collision layer/mask is zeroed (see
# _disable_drag_collision), so it stops overlapping the area - that is why
# _update_cursor checks current_dragging_object (carried) before this (in range).
func _has_draggable_in_range() -> bool:
	for body in drag_area.get_overlapping_bodies():
		if body is CollisionObject and body.has_meta("draggable") and body.get_meta("draggable"):
			return true
	return false

# Drives the center-screen interaction cursor for drag-able props:
#   - carrying an object          -> clenched-hand  (T_hold_interaction)
#   - drag-able object in range   -> open-hand      (T_start_hold_interaction)
#   - otherwise (incl. menu open) -> cursor hidden
#
# "Carrying" keys off current_dragging_object rather than is_dragging so the
# clenched hand stays up while airborne: is_dragging is forced false in the air,
# but the object is still parented to the player and visibly carried.
func _update_cursor() -> void:
	if interaction_cursor == null:
		return
	if not _player_not_in_inventory():
		interaction_cursor.hide_cursor()
		return
	var in_range: bool = _has_draggable_in_range()
	# Consume the release-bridge: pretend the just-dropped object is still in
	# range for this single frame so the open-hand prompt does not blink out the
	# moment E is released.
	if _drag_just_released:
		_drag_just_released = false
		in_range = true
		$StoneSound.playing = false
	if current_dragging_object != null:
		interaction_cursor.show_hold()
		if not $StoneSound.playing:
			$StoneSound.play()
	elif in_range:
		interaction_cursor.show_start()
	else:
		interaction_cursor.hide_cursor()

# DOWNGRADE NOTE: Godot 3.x has no Node.reparent(); replicate it while keeping
# the global transform (matches the Godot 4 reparent default).
func _reparent_keep_global(node: Spatial, new_parent: Node) -> void:
	var keep_transform = node.global_transform
	var prev_parent = node.get_parent()
	if prev_parent != null:
		prev_parent.remove_child(node)
	new_parent.add_child(node)
	node.global_transform = keep_transform

func item_exited_from_interact_area(thing: Spatial):
	var prompt_owner = _get_prompt_owner(thing)
	if prompt_owner != null:
		prompt_owner.hide_text()

func new_item_in_interact_area(thing: Spatial):
	var prompt_owner = _get_prompt_owner(thing)
	if prompt_owner != null:
		prompt_owner.show_text(self)

# Returns the nearest ancestor of `thing` that can show an interaction prompt:
# a PickupBase (inventory pickups such as the frying pan) OR any other node exposing
# show_text()/hide_text() (e.g. a Draggable prop like the StaticWorld cube). This is
# what makes the floating "E" appear for both pickups and draggable props.
func _get_prompt_owner(thing) -> Node:
	var node = thing
	while node != null:
		if node is PickupBase:
			return node
		if node.has_method("show_text") and node.has_method("hide_text"):
			return node
		node = node.get_parent()
	return null

func _input(event):
	if _player_not_in_inventory():
		if not is_dragging:
			if event is InputEventMouseMotion:
				self.rotate_y(deg2rad(event.relative.x * mouse_sensitivity * -1))

				# Drive vertical look (pitch) from a dedicated accumulator clamped to
				# +/- PITCH_LIMIT around the helper's neutral rotation. The previous
				# code read rotation_degrees.x back, clamped it to [-70, 70] and added
				# 90 every frame; because the helper's neutral X is ~-90, that snapped
				# and then pinned the value, so the view got stuck looking up/back and
				# could never look below the horizon.
				pitch += event.relative.y * mouse_sensitivity
				pitch = clamp(pitch, -PITCH_LIMIT, PITCH_LIMIT)
				var helper_rot = rotation_helper.rotation_degrees
				helper_rot.x = _base_pitch_deg + pitch
				rotation_helper.rotation_degrees = helper_rot
			if event is InputEventMouseButton:
				if event.is_pressed() and event.get_button_index() == BUTTON_LEFT:
					arm.use_weapon()
