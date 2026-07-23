extends HittableBase

var destroyed: bool = false

# DOWNGRADE NOTE: @onready -> onready. Node renamed CollisionShape3D -> CollisionShape.
onready var destruction = $Destruction
onready var my_collision = $CollisionShape

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
