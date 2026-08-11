extends Spatial
# One-shot pressure button.
#
# The first time the player gets within `trigger_distance` of the Ball (the
# button cap) it plays the table-lamp "click" sound and deletes the WALL child,
# opening the passage that the wall was blocking. Subsequent approaches do
# nothing — the trigger is latched via `_triggered` and `_physics_process` is
# turned off once it fires.
#
# Mounted on the `button` Spatial node of scenes/new/new.tscn, which owns both
# the `Ball` (proximity target) and the `WALL` (StaticBody to be removed).

# Horizontal (XZ) distance in metres from the Ball at which the button fires.
export(float) var trigger_distance := 2.0
# Group that identifies the player body (Player.gd registers into "player").
export(String) var player_group := "player"
# Sound played once when the button is pressed.
export(AudioStream) var sound_stream: AudioStream = preload("res://assets/sounds/off-button-on-table-lamp.mp3")

onready var _ball: Spatial = $Ball
onready var _wall: Node = $WALL

var _triggered := false


func _ready() -> void:
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _triggered:
		return
	var player := _get_player()
	if player == null or _ball == null:
		return
	# Horizontal distance only: the button rests on the floor while the player's
	# origin (capsule centre) sits ~1 m above ground, so a full 3D distance would
	# be dominated by that constant Y offset and demand an oversized radius.
	var d := _horizontal_distance(player.global_transform.origin, _ball.global_transform.origin)
	if d <= trigger_distance:
		_trigger()


func _get_player() -> Spatial:
	for p in get_tree().get_nodes_in_group(player_group):
		if p is Spatial:
			return p
	return null


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _trigger() -> void:
	# Latch first: queue_free() is deferred, so without this a second physics
	# tick could fire the sound/trigger again before the wall is gone.
	_triggered = true
	set_physics_process(false)
	_play_sound()
	if _wall != null:
		_wall.queue_free()


func _play_sound() -> void:
	if sound_stream == null:
		return
	# Positional cue at the button so it fades with distance like the rest of
	# the level's world audio. Self-cleaning once it finishes playing.
	var s := AudioStreamPlayer3D.new()
	s.stream = sound_stream
	s.global_transform = _ball.global_transform
	add_child(s)
	s.connect("finished", s, "queue_free")
	s.play()
