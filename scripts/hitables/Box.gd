extends HittableBase

var destroyed: bool = false

# DOWNGRADE NOTE: @onready -> onready. Node renamed CollisionShape3D -> CollisionShape.
onready var destruction = $Destruction
onready var my_collision = $CollisionShape

func _ready():
	# Mark this box as grabbable by the player's drag system (Player.get_is_dragging
	# looks for the "draggable" meta). The Godot-4 scene carried this as node
	# metadata on test.tscn; it was dropped during the 3.x scene rebuild, which is
	# why holding E no longer picked anything up. Setting it here is version-safe.
	set_meta("draggable", true)

func get_hit() -> void:
	if not destroyed:
		destruction.Destroy(0, Vector3.ZERO)
		# DOWNGRADE NOTE: Godot 3.x has no process_mode property; disable every
		# processing path individually to match PROCESS_MODE_DISABLED.
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		my_collision.queue_free()
		destroyed = true
