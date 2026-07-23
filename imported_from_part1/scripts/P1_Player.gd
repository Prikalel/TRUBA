extends Camera

# MIGRATED FROM part1/scripts/Player.gd  (file -> P1_Player.gd).
# Input stays on raw scancodes (KEY_W/A/S/D) — web-safe and no clash with
# part2's action-based input map. No class_name in the original, so none added.

var forward: float = 0.0
var rotating: bool = false
const SPEED: float = 2.0
const ROTATION_SPEED: float = 8.0
const FLOAT_EPSILON = 0.01

# WEB-SAFE: converted from Thread/OS.delay_msec.
# The original launched a worker Thread (Thread.new()/thread.start(self,"do_stuff",[cnt,pos]))
# that ran a blocking `while i < cnt` loop calling global_rotate + lerp + OS.delay_msec.
# The exact same per-degree rotation + per-degree lerp is now advanced across frames here.
var _rot_cnt: int = 0          # total 1-degree steps to perform (== abs(cnt))
var _rot_i: int = 0            # steps completed so far
var _rot_sign: float = 1.0     # turn direction (+/-), reproduces original sign_to
var _rot_delay_ms: int = 0     # per-step delay == int(cnt / ROTATION_SPEED), same as original
var _rot_elapsed_ms: float = 0.0
var _rot_axis: Vector3 = Vector3.UP          # global Y axis captured at turn start
var _rot_step_angle: float = 0.0             # == -0.0174533 * sign_to (1 degree, with sign)
var _rot_start_pos: Vector3 = Vector3.ZERO
var _rot_pos_to: Vector3 = Vector3.ZERO


# WEB-SAFE: converted from Thread do_stuff().
func _advance_rotation(delta: float) -> void:
	if not rotating:
		return
	_rot_elapsed_ms += delta * 1000.0
	# Perform every 1-degree step whose per-step delay has elapsed this frame.
	# (Bounded loop: at most a handful of steps per frame -> no busy-wait, web-safe.)
	while rotating and _rot_i < _rot_cnt and _rot_elapsed_ms >= float(_rot_delay_ms):
		_rot_elapsed_ms -= float(_rot_delay_ms)
		global_rotate(_rot_axis, _rot_step_angle)
		_rot_i += 1
		global_translation = _rot_start_pos.linear_interpolate(_rot_pos_to, float(_rot_i) / float(_rot_cnt))
		if _rot_i >= _rot_cnt:
			global_translation = _rot_pos_to
			rotating = false
			break


# WEB-SAFE: converted from start_rotating() which launched a worker Thread.
func start_rotating(cnt: int, pos: Vector3) -> void:
	if rotating:
		return
	# Preserve original sign/direction semantics from do_stuff().
	_rot_sign = 1.0
	_rot_cnt = cnt
	if cnt < 0:
		_rot_sign = -1.0
		_rot_cnt = -cnt
	if _rot_cnt == 0:
		rotating = false
		return
	_rot_step_angle = -0.0174533 * _rot_sign
	_rot_delay_ms = int(float(_rot_cnt) / ROTATION_SPEED)
	if _rot_delay_ms <= 0:
		_rot_delay_ms = 1
	_rot_axis = self.global_transform.basis.y.normalized()
	_rot_start_pos = self.global_translation
	_rot_pos_to = pos
	_rot_i = 0
	_rot_elapsed_ms = 0.0
	rotating = true


func _input(event):
	if event is InputEventKey:
		if event.scancode == KEY_W:
			self.forward = float(event.pressed) * -1.0
		if event.pressed and not self.rotating:
			if event.scancode == KEY_S:
				start_rotating(180, self.global_translation)
			elif len($StaticBody.get_overlapping_areas()) > 0:
				var area_0 = $StaticBody.get_overlapping_areas()[0]
				if area_0 is P1_StaticBodyDirection:
					var st = area_0
					var pos: Vector3 = st.get_main_point_position()
					if event.scancode == KEY_A:
						start_rotating(-90, pos)
					elif event.scancode == KEY_D:
						start_rotating(90, pos)


func _process(delta: float):
	var can_move_forward: bool = true
	if len($StaticBody.get_overlapping_areas()) > 0:
		var area_0 = $StaticBody.get_overlapping_areas()[0]
		if area_0 is P1_StaticBodyDirection:
			can_move_forward = false
			var st = area_0
			for direction in st.directions:
				if compare_floats_rotation(direction, self.global_rotation.y):
					can_move_forward = true
					break
	if not self.rotating:
		$ClothesPlayer.volume_db = -80
		if self.forward != 0.0 and can_move_forward:
			$AudioStreamPlayer.volume_db = 0
			self.global_transform.origin += get_global_transform().basis.z.normalized() * SPEED * self.forward * delta
		else:
			$AudioStreamPlayer.volume_db = -80
	else:
		$AudioStreamPlayer.volume_db = -80
		$ClothesPlayer.volume_db = 0
	# WEB-SAFE: advance the turn animation that previously ran on a Thread.
	_advance_rotation(delta)


static func compare_floats_rotation(a, b, epsilon = FLOAT_EPSILON):
	var absss: float = abs(a - b)
	if (a < 0 and b > 0) or (b < 0 and a > 0):
		return absss <= epsilon or abs(absss - 2 * PI) <= epsilon
	return absss <= epsilon
