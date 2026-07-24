extends Spatial
# Adds a pulsing back-face outline (see shaders/outline.shader) to every mesh under
# the parent object. Opacity fades with the player's distance to the object and
# pulses over time. The outline is depth-tested, so it is occluded by closer geometry.
#
# Attach as a child of the interactable (the cube / box). The player is looked up via
# the "player" group, so no node paths or file I/O are involved (HTML5-safe).

const OUTLINE_SHADER := preload("res://shaders/outline.shader")
const OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 1.0) # white interactable highlight
const NEAR_DISTANCE := 1.5 # outline fully opaque at/inside this distance
const FAR_DISTANCE := 5.0  # outline fades to nothing at/past this distance
const PULSE_SPEED := 5.0   # pulsation speed in radians/second
const PULSE_MIN := 0.35    # lowest outline opacity during the pulse (0..1)

var _outline_material: ShaderMaterial
var _outline_copies: Array = []
var _player: Spatial = null
var _time := 0.0

func _ready() -> void:
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_param("outline_color", Color(OUTLINE_COLOR.r, OUTLINE_COLOR.g, OUTLINE_COLOR.b, 0.0))
	# Defer the build one frame so the whole object subtree is ready before we scan it.
	call_deferred("_build")

func _build() -> void:
	var meshes: Array = []
	_collect_meshes(get_parent(), meshes)
	for mesh_node in meshes:
		_create_outline_copy(mesh_node)

func _collect_meshes(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance or child is CSGMesh:
			out.append(child)
		_collect_meshes(child, out)

func _create_outline_copy(mesh_node: Spatial) -> void:
	# Both MeshInstance and CSGMesh expose a `mesh` property (ArrayMesh / PrimitiveMesh).
	var src_mesh = mesh_node.get("mesh")
	if src_mesh == null:
		return
	var dupe := MeshInstance.new()
	dupe.name = "Outline"
	dupe.mesh = src_mesh
	dupe.material_override = _outline_material
	# Godot 3 does not expose SHADOW_CASTING_OFF as a flat GDScript constant; 0 == off.
	dupe.cast_shadow = 0
	# Parent the copy next to the source mesh so it shares the exact same transform.
	mesh_node.get_parent().add_child(dupe)
	dupe.transform = mesh_node.transform
	_outline_copies.append(dupe)

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		var players = get_tree().get_nodes_in_group("player")
		if players.empty():
			return
		_player = players[0] as Spatial
	var obj = get_parent() as Spatial
	if obj == null or _player == null:
		return
	# Distance from the object's centre to the player.
	var d = obj.global_transform.origin.distance_to(_player.global_transform.origin)
	var t = clamp((FAR_DISTANCE - d) / (FAR_DISTANCE - NEAR_DISTANCE), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t) # smoothstep: gentle fade near both ends
	# Animate: pulse the outline opacity between PULSE_MIN and full, scaled by distance.
	_time += _delta
	var pulse: float = 0.5 + 0.5 * sin(_time * PULSE_SPEED) # 0..1
	var a: float = t * lerp(PULSE_MIN, 1.0, pulse)
	_outline_material.set_shader_param("outline_color", Color(OUTLINE_COLOR.r, OUTLINE_COLOR.g, OUTLINE_COLOR.b, a))
