extends Spatial
# Spawned in place of an intact Box (see Box.gd -> get_hit()) and turns every mesh
# fragment of the imported box_broken glTF into a physics shard: each MeshInstance
# child is wrapped in a RigidBody with a convex CollisionShape and given an outward
# + upward scatter velocity, so the broken box "explodes" apart and the pieces then
# settle under gravity (i.e. physics is enabled on the fragments, as requested).

const SCATTER_SPEED := 3.5
const UPWARD_BIAS := 1.5

func _ready() -> void:
	_shatter()

func _shatter() -> void:
	# Snapshot first: we reparent/free children while iterating.
	var pieces: Array = []
	for child in get_children():
		if child is MeshInstance:
			pieces.append(child)
	for piece in pieces:
		_make_shard(piece)

func _make_shard(mesh_inst: MeshInstance) -> void:
	var mesh: ArrayMesh = mesh_inst.mesh as ArrayMesh
	if mesh == null:
		return
	# Position the body where the fragment sits, then re-centre the mesh on it so the
	# convex collision (built from that same mesh) lines up with the visuals.
	var piece_origin: Vector3 = mesh_inst.translation
	var body := RigidBody.new()
	# DOWNGRADE NOTE: Godot 3.x Spatial uses .translation (not .position).
	body.translation = piece_origin
	body.collision_layer = 1
	body.collision_mask = 1

	mesh_inst.get_parent().remove_child(mesh_inst)
	mesh_inst.translation = Vector3.ZERO
	body.add_child(mesh_inst)

	var col := CollisionShape.new()
	col.shape = mesh.create_convex_shape(true, false)
	body.add_child(col)

	add_child(body)

	# Scatter outward from the box centre, with a bit of upward lift and tumble.
	var dir := (Vector3(piece_origin.x, 0.0, piece_origin.z) + Vector3(0.0, UPWARD_BIAS, 0.0)).normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector3.UP
	body.linear_velocity = dir * SCATTER_SPEED
	body.angular_velocity = Vector3(rand_range(-3.0, 3.0), rand_range(-3.0, 3.0), rand_range(-3.0, 3.0))
