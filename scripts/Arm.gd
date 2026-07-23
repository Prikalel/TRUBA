extends Spatial
class_name Arm

const ARM_SHAKE_AMPLITUDE = 0.03
const ARM_SHAKE_SPEED = 0.03
const WEAPON_PREPARE_SPEED = 1
const WEAPON_PREPARE_AMPLITUDE = 0.07

# DOWNGRADE NOTE: Godot 3.x has no typed arrays; use a plain Array.
var hands: Array = [null, null]

var weapon_preparing: bool = false
var arm_origin_y_position: float
var arm_shake_time: float = 0
var current_hand: int = 0

func listen_weapon_change(inv: Inventory) -> void:
	# DOWNGRADE NOTE: Godot 3.x connect takes (signal, target, method_name).
	inv.connect("weapon_in_hand_slot", self, "_on_weapon_to_hand_assigned")

func _on_weapon_to_hand_assigned(hand_slot_indx: int, pickup_id: int) -> void:
	var new_weapon: WeaponObj = PickupData.weapon_by_id(pickup_id)
	if (new_weapon == null):
		push_error("Error resolving pickup id " + str(pickup_id))
	if hands[hand_slot_indx] != null:
		remove_child(hands[hand_slot_indx])
		hands[hand_slot_indx].queue_free()
	# DOWNGRADE NOTE: Godot 3.x PackedScene.instance() replaces instantiate().
	var weapon_instance: WeaponBase = load(new_weapon.hand_scene).instance() as WeaponBase
	hands[hand_slot_indx] = weapon_instance
	add_child(weapon_instance)
	if (hand_slot_indx != current_hand):
		weapon_instance.hide()
	else:
		weapon_preparing = true
		arm_shake_time = -PI / 2

func _ready():
	# DOWNGRADE NOTE: Godot 3.x Spatial uses .translation (not .position).
	arm_origin_y_position = translation.y

func shake(velocity: Vector3) -> void:
	if (not weapon_preparing):
		arm_shake_time += velocity.length() * ARM_SHAKE_SPEED
		translation.y = arm_origin_y_position + ARM_SHAKE_AMPLITUDE * sin(arm_shake_time)
		if (arm_shake_time >= 2 * PI):
			arm_shake_time -= 2 * PI

func _process(delta):
	if weapon_preparing:
		arm_shake_time += delta * WEAPON_PREPARE_SPEED
		translation.y = arm_origin_y_position + WEAPON_PREPARE_AMPLITUDE * sin(arm_shake_time)
		if (arm_shake_time >= 0):
			weapon_preparing = false

func use_weapon() -> void:
	var weapon: WeaponBase = hands[current_hand] as WeaponBase
	if (weapon != null and not weapon_preparing):
		weapon.do_hit()
