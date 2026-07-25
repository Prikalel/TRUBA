extends CSGBox

# MIGRATED FROM part1/scripts/ScreemerBox.gd  (file -> P1_ScreemerBox.gd).

var triggered: bool = false
const SPEED: float = 20.0

# WEB-SAFE: converted from Thread/OS.delay_msec.
# The original launched a worker Thread (Thread.new()/thread.start(self,"do_stuff"))
# that slid this box toward the player in a `while i <= time` loop with OS.delay_msec(1),
# then hid it after OS.delay_msec(1500) and stopped the scream. That is now frame-driven.
var _moving: bool = false
var _hiding: bool = false
var _start_position: Vector3 = Vector3.ZERO
var _pos_to: Vector3 = Vector3.ZERO
var _t: float = 0.0               # interpolation param 0..1 across the slide
var _slide_duration: float = 0.0  # seconds the slide takes (reproduces original SPEED=10 slide)
var _hide_timer: float = 0.0      # replaces OS.delay_msec(1500) hide delay


# WEB-SAFE: converted from Thread do_stuff() — slide (was while+OS.delay_msec(1)) then hide (was OS.delay_msec(1500)).
func _process(delta: float):
	if _moving:
		if _slide_duration > 0.0:
			_t += delta / _slide_duration
		else:
			_t = 1.0
		if _t >= 1.0:
			_t = 1.0
			global_translation = _pos_to
			_moving = false
			# WEB-SAFE: OS.delay_msec(1500) hide delay -> counted-down timer.
			self.hide()
			_hiding = true
			_hide_timer = 1.5
		else:
			global_translation = _start_position.linear_interpolate(_pos_to, _t)
	elif _hiding:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_hiding = false
			$AudioStreamPlayer3D.stop()


# WEB-SAFE: converted from start_moving() which launched a worker Thread.
func start_moving():
	if _moving or _hiding:
		return
	_pos_to = $StaticBody/Point.global_translation
	_start_position = self.global_translation
	var dist: float = (_start_position - _pos_to).length()
	# Reproduce the original slide visual: linear move toward the player at SPEED units/sec.
	_slide_duration = dist / SPEED
	if _slide_duration <= 0.0:
		_slide_duration = 0.0001
	_t = 0.0
	_moving = true


func _on_StaticBody_area_shape_entered(area_rid, area, area_shape_index, local_shape_index):
	if self.triggered:
		return
	self.triggered = true
	$StaticBody.set_deferred("monitoring", false)
	start_moving()
	$AudioStreamPlayer3D.play()
