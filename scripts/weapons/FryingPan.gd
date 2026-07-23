extends WeaponBase
class_name FryingPan

var pan_speed = 4
# DOWNGRADE NOTE: deg_to_rad -> deg2rad.
var end_rotation: Vector3 = Vector3(0, deg2rad(43), 0)
var pan_start_position: Vector3
var pan_start_rotation: Vector3
var path_offset: float = 0
var is_moving: bool = false

var pan: Spatial
# DOWNGRADE NOTE: node types Path3D -> Path, Area3D -> Area.
var pan_path: Path
var hit_area: Area

func _ready():
	pan = $FryingPan
	# DOWNGRADE NOTE: scene node renamed Path3D -> Path.
	pan_path = $Path
	hit_area = $HitArea

func do_hit() -> void:
	if _start_hit():
		var list = hit_area.get_overlapping_bodies()
		for i in range(len(list)):
			var collision_node: HittableBase = Utils.get_suitable_parent(list[i] as Node, HittableBase)
			if collision_node != null:
				collision_node.get_hit()

func _start_hit() -> bool:
	if not is_moving:
		# DOWNGRADE NOTE: Godot 3.x Spatial uses .translation (not .position).
		pan_start_position = pan.translation
		pan_start_rotation = pan.rotation
		path_offset = 0
		is_moving = true
		return true
	return false

func _stop_moving() -> void:
	pan.translation = pan_start_position
	pan.rotation = pan_start_rotation
	path_offset = 0
	is_moving = false

func _process(delta):
	if is_moving:
		var current_pos = pan_path.get_curve().sample_baked(path_offset)
		pan.translation = current_pos
		path_offset += delta * pan_speed
		var alpha = path_offset / pan_path.get_curve().get_baked_length()
		# DOWNGRADE NOTE: Godot 3.x Vector3 has no .lerp(); use linear_interpolate.
		pan.rotation = pan_start_rotation.linear_interpolate(end_rotation, alpha)
		if (alpha >= 1):
			pan_speed *= -1
		elif (alpha <= 0):
			pan_speed *= -1
			_stop_moving()
