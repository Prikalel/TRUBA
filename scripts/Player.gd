extends KinematicBody

const GRAVITY = -12
const MAX_SPEED = 6
const MAX_SPEED_CRAWLING = 3
const JUMP_SPEED = 5
const CRAWL_ACCEL_MULTIPLIER = 3
const ACCEL = 4.5
const DEACCEL = 16
const MAX_SLOPE_ANGLE = 40
const MAX_FALLING_SPEED = 7
const HTARGET_WHILE_FALLING_DEACCEL = 3

# DOWNGRADE NOTE: Godot 3.x KinematicBody has no built-in velocity member and
# move_and_slide() requires velocity as an argument, so it is stored here.
var velocity: Vector3 = Vector3.ZERO
# DOWNGRADE NOTE: Godot 3.x KinematicBody has no floor_max_angle property; it is
# passed straight into move_and_slide() instead.
var floor_max_angle: float = deg2rad(MAX_SLOPE_ANGLE)

var dir: Vector3 = Vector3()
var last_htarget: Vector3 = Vector3()
var is_dragging: bool = false

var camera: Camera
var rotation_helper: Spatial
var player_capsule: Capsule
var arm: Arm
var drag_area: Area
var inventory: Inventory

var current_dragging_object: CollisionObject = null

var mouse_sensitivity: float = 0.05

func _ready():
	camera = $Body_CollisionShape/Rotation_Helper/Camera
	rotation_helper = $Body_CollisionShape/Rotation_Helper
	player_capsule = $Body_CollisionShape as Capsule
	arm = $Body_CollisionShape/Rotation_Helper/Arm as Arm
	drag_area = $Body_CollisionShape/DragArea as Area
	inventory = $Inventory as Inventory
	arm.listen_weapon_change(inventory)

func _player_not_in_inventory() -> bool:
	return not inventory.visible

func _physics_process(delta):
	if _player_not_in_inventory():
		process_input()
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
	else:
		is_dragging = false
		player_capsule.disable_crawling()

	if not is_dragging and Input.is_action_just_pressed("interaction"):
		inventory.find_pickup_in_area(drag_area)

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
					_reparent_keep_global(current_dragging_object, self)
					break
	return current_dragging_object != null

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
	var pickup: PickupBase = Utils.get_suitable_parent(thing, PickupBase) as PickupBase
	if pickup != null:
		pickup.hide_text()

func new_item_in_interact_area(thing: Spatial):
	var pickup: PickupBase = Utils.get_suitable_parent(thing, PickupBase) as PickupBase
	if pickup != null:
		pickup.show_text(self)

func _input(event):
	if _player_not_in_inventory():
		if not is_dragging:
			if event is InputEventMouseMotion:
				rotation_helper.rotate_x(deg2rad(event.relative.y * mouse_sensitivity))
				self.rotate_y(deg2rad(event.relative.x * mouse_sensitivity * -1))

				var camera_rot = rotation_helper.rotation_degrees
				camera_rot.x = clamp(camera_rot.x, -70, 70)
				rotation_helper.rotation_degrees = camera_rot
			if event is InputEventMouseButton:
				if event.is_pressed() and event.get_button_index() == BUTTON_LEFT:
					arm.use_weapon()
