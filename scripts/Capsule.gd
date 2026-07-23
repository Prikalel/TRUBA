extends CollisionShape
class_name Capsule

const CAPSULE_NORMAL_HEIGHT = 2
const CAPSULE_CRAWLING_HEIGHT = 1
const CAPSULE_CHANGE_HEIGHT_SPEED = 2.5

var head_area: Area
var rotation_helper: Spatial
var _capsule_height: float
var _is_crawling: bool = false

func _ready():
	head_area = $HeadArea as Area
	rotation_helper = $Rotation_Helper as Spatial
	_capsule_height = _set_capsule_height(CAPSULE_NORMAL_HEIGHT)

func disable_crawling() -> void:
	_is_crawling = false

func toggle_crawling() -> void:
	_is_crawling = not _is_crawling

func get_crawling() -> bool:
	return _is_crawling or not Utils.floats_equal(_capsule_height, CAPSULE_NORMAL_HEIGHT)

func _is_under_something(capsule_global_position: Vector3) -> bool:
	var list = head_area.get_overlapping_bodies()
	for i in range(len(list)):
		# DOWNGRADE NOTE: Godot 3.x Spatial uses global_transform.origin (not global_position).
		var collision_position: Vector3 = (list[i] as Spatial).global_transform.origin
		if (collision_position - capsule_global_position).y > 0:
			return true
	return false

func _change_height_if_crawling(delta: float) -> void:
	var capsule_height_delta: float
	if _is_crawling:
		if _capsule_height > CAPSULE_CRAWLING_HEIGHT:
			capsule_height_delta = -CAPSULE_CHANGE_HEIGHT_SPEED * delta
		elif _capsule_height < CAPSULE_CRAWLING_HEIGHT:
			capsule_height_delta = CAPSULE_CRAWLING_HEIGHT - _capsule_height
	else:
		if _capsule_height < CAPSULE_NORMAL_HEIGHT:
			capsule_height_delta = CAPSULE_CHANGE_HEIGHT_SPEED * delta
		elif _capsule_height > CAPSULE_NORMAL_HEIGHT:
			capsule_height_delta = CAPSULE_NORMAL_HEIGHT - _capsule_height

	if not Utils.floats_equal(capsule_height_delta, 0):
		_capsule_height = _set_capsule_height(_capsule_height + capsule_height_delta)

func _set_capsule_height(new_height: float) -> float:
	# DOWNGRADE NOTE: Godot 3.x resource/shape type is CapsuleShape (no 3D suffix).
	var capsule: CapsuleShape = shape as CapsuleShape
	if new_height < capsule.height or not _is_under_something(global_transform.origin):
		capsule.height = new_height
		var new_camera_y_pos: float = float(capsule.height / 2) - capsule.radius
		# Rotation_Helper's parent (Body_CollisionShape) carries a 90deg X rotation, so
		# the helper's LOCAL +Z maps to WORLD +Y (and local +Y maps to world +Z). To
		# raise/lower the camera vertically when crouching we must therefore drive the
		# helper's local origin.z, not origin.y (the latter slid the camera forward/back,
		# which is why crouching appeared to do nothing).
		rotation_helper.transform.origin.z = new_camera_y_pos
	return capsule.height

func _physics_process(delta):
	_change_height_if_crawling(delta)
