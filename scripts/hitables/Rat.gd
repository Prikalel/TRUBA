extends PickupBase

var rat: Spatial
var path: Path
var current_offset: float = 0
var rat_speed = 2
var is_killed: bool = false

onready var particles = get_node("rat/StaticBody/Spatial/Particles") 

func get_hit() -> void:
	if not is_killed:
		# DOWNGRADE NOTE: Godot 3 Spatial has no global_rotation (Godot-4-only); set the global basis from Euler.
		var _gt = rat.global_transform
		_gt.basis = Basis(Vector3(0, 0, deg2rad(74)))
		rat.global_transform = _gt
		is_killed = true
		# DOWNGRADE NOTE: scene nodes renamed StaticBody3D->StaticBody, GPUParticles3D->Particles.
		particles.visible = true
		# Now lootable: surface the floating "E" right away. The player just swung
		# the pan, so they are standing next to the rat - and Player._update_prompts
		# caches already-prompted owners, so without this the prompt would only
		# (re)appear after the player steps out of and back into the drag area.
		var _player = _get_player()
		if _player != null:
			show_text(_player)
		# DOWNGRADE NOTE: Godot 3 Spatial has no global_rotation (Godot-4-only); set the global basis from Euler.
		#var _pgt = particles.global_transform
		#_pgt.basis = Basis(Vector3(0, 0, 0))
		#particles.global_transform = _pgt

# Only surface the loot prompt once the rat is dead; PickupBase's show_text would
# otherwise pop a floating "E" over a live, walking rat whenever it enters range.
func show_text(player_node) -> void:
	if is_killed:
		.show_text(player_node)

# Lootable only after being killed.
func can_be_picked_up() -> bool:
	return is_killed

func _get_player():
	var _players = get_tree().get_nodes_in_group("player")
	if _players.size() > 0:
		return _players[0]
	return null

func _ready():
	rat = $rat
	# DOWNGRADE NOTE: scene node renamed Path3D -> Path.
	path = $Path
	particles = get_node("rat/StaticBody/Spatial/Particles")
	particles.visible = false
	# PickupBase.pickup_id defaults to -1; bind this rat to the RAT food entry so it
	# can be looted into the inventory's second row once it has been killed.
	pickup_id = PickupId.RAT

func _process(delta):
	if not is_killed:
		# DOWNGRADE NOTE: Godot 3.x Spatial uses global_transform.origin (not global_position).
		# DOWNGRADE NOTE: Curve3D.sample_baked() (Godot 4) -> Curve3D.interpolate_baked() (Godot 3.x). WEB-SAFE: single-threaded.
		var new_position = global_transform.origin + path.get_curve().interpolate_baked(current_offset)
		rat.look_at_from_position(new_position, rat.global_transform.origin, Vector3.UP)
		rat.global_transform.origin = new_position
		current_offset += delta * rat_speed
		if (current_offset > path.get_curve().get_baked_length()):
			current_offset -= path.get_curve().get_baked_length()
