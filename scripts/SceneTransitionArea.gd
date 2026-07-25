extends Area
# Trigger volume that fades the screen to black, shows an animated loading
# spinner, and loads the next scene ASYNCHRONOUSLY (ResourceLoader.
# load_interactive) so the spinner keeps animating while a big level loads —
# instead of a frozen black screen.
#
# Flow: player enters trigger -> fade ColorRect to black (fade_duration) -> on
# fade complete, instance the loading-animation scene (centered) on top and
# start polling the interactive loader a few ms per frame. Once the target
# PackedScene is fully loaded, change_scene_to() swaps to it (instantiation is
# fast; the slow part is the incremental disk load, which now happens between
# animation frames).

# PackedScene path to load once the fade-out completes.
export var target_scene: String = "res://imported_from_part1/scenes/part1_horror.tscn"
# Fade-to-black duration in seconds.
export var fade_duration: float = 1.0
# Physics bodies in this group are treated as "the player" and trigger the
# transition. Works with any player representation — e.g. part1_horror's
# Camera-based player exposes a small StaticBody proxy in this group.
export var player_group: String = "player"
# Loading-screen scene (animated spinner). Centered on screen at runtime so it
# is correct at any resolution.
export var loading_scene: String = "res://assets/anims/loading-animation.tscn"
# Max milliseconds spent loading per frame while the spinner animates. Lower =
# smoother animation but slower total load; higher = faster load, choppier spin.
export var load_time_budget_ms: int = 12
# --- Key-gated "door" logic (opt-in) -----------------------------------------
# When true, the transition only fires if the player carries the item whose id
# is `required_key_id`. Entering WITHOUT the key plays the one-shot "BAD
# ATTEMPT" cue (replayed on every re-entry) and does NOT transition; entering
# WITH the key plays "UNLOCK" and then fades/loads as usual.
#
# Default is false on purpose: this script is also used for plain level links
# (test2 -> test3, etc.) that must keep their original "step in -> fade out"
# behaviour and must NOT play any audio. Flip it to true only on door-style
# transitions such as test3's SewerTransitionArea.
export var requires_key: bool = false
# PickupData item id that unlocks a key-gated transition (test3's sewer gate
# uses the key, id 2).
export var required_key_id: int = 2

var _transitioning: bool = false
var _fade_rect: ColorRect
var _overlay: CanvasLayer
var _loader: ResourceInteractiveLoader
var _loading: bool = false
# Optional AudioStreamPlayer(3D) children that play the door cues. Only present
# on key-gated transitions (test3's SewerTransitionArea defines "UNLOCK" and
# "BAD ATTEMPT"); looked up by name so plain transitions need no audio nodes.
const _UNLOCK_NODE := "UNLOCK"
const _BAD_ATTEMPT_NODE := "BAD ATTEMPT"


func _ready() -> void:
	# Build a fullscreen black overlay on the very top layer; starts invisible.
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fade_rect)
	# Fill the whole screen (anchors 0..1, no margins). Done after adding to the
	# tree so the Control picks up the viewport rect of the CanvasLayer.
	_fade_rect.anchor_right = 1.0
	_fade_rect.anchor_bottom = 1.0
	_fade_rect.margin_left = 0.0
	_fade_rect.margin_top = 0.0
	_fade_rect.margin_right = 0.0
	_fade_rect.margin_bottom = 0.0

	connect("body_entered", self, "_on_body_entered")


func _on_body_entered(body: Node) -> void:
	# Only the player triggers the transition; ignore walls / props that may
	# also overlap the trigger volume.
	if not _is_player(body):
		return
	if _transitioning:
		return
	if requires_key and not _player_has_required_key():
		# Locked door: play the "can't open this" cue and stay put. The area
		# keeps monitoring, so walking out and back in (banging on the door)
		# replays the sound on every entry until the player actually has the key.
		_play_door_cue(_BAD_ATTEMPT_NODE)
		return
	# Unlocked (or not key-gated at all): announce the unlock on door-style
	# transitions, then fade to black and load the next scene as usual.
	if requires_key:
		_play_door_cue(_UNLOCK_NODE)
	_transitioning = true
	# Stop reacting to further overlaps once a transition has started.
	set_deferred("monitoring", false)
	_fade_out()


# --- Key-gated door helpers --------------------------------------------------

func _player_has_required_key() -> bool:
	var inv: Inventory = _get_player_inventory()
	if inv == null or inv.grid == null:
		return false
	for slot in inv.grid.slots:
		if slot != null and slot.current != null and slot.current.id == required_key_id:
			return true
	return false


func _get_player_inventory() -> Inventory:
	# The body that entered is recognised via the player group, but the actual
	# Inventory control lives on the player root (Player.tscn exposes $Inventory
	# and Player.gd caches it as `inventory`). Search the group for whichever
	# member owns an Inventory so this stays decoupled from node paths.
	for p in get_tree().get_nodes_in_group(player_group):
		var inv = p.get_node_or_null("Inventory")
		if inv is Inventory:
			return inv
	return null


func _play_door_cue(node_name: String) -> void:
	# Duck-typed so it works with AudioStreamPlayer / 2D / 3D alike. play() with
	# no argument restarts the stream from 0, so repeated door-banging retriggers
	# the cue every time instead of letting it run on.
	var player = get_node_or_null(node_name)
	if player != null and player.has_method("play"):
		player.play()


func _is_player(node: Node) -> bool:
	# Recognise the player either by the configured group (preferred — works
	# across levels with different player implementations) or by the legacy
	# node name "Player" (the test2 KinematicBody).
	return node.is_in_group(player_group) or node.name == "Player"


func _fade_out() -> void:
	var tween := Tween.new()
	add_child(tween)
	tween.interpolate_property(
		_fade_rect, "color:a",
		0.0, 1.0,
		fade_duration,
		Tween.TRANS_LINEAR, Tween.EASE_IN
	)
	tween.connect("tween_completed", self, "_on_fade_completed")
	tween.start()


func _on_fade_completed(_object: Object, _key: NodePath) -> void:
	# Screen is fully black now — reveal the spinner and start loading.
	_show_loading_spinner()
	_start_async_load()


func _show_loading_spinner() -> void:
	var packed := load(loading_scene) as PackedScene
	if packed == null:
		push_error("SceneTransitionArea: loading_scene '%s' could not be loaded" % loading_scene)
		return
	var spinner_root := packed.instance()
	_overlay.add_child(spinner_root)
	# Center the spinner sprite on screen (resolution-independent). The
	# loading-animation scene also sets a default-centred position, but the
	# real viewport may differ at runtime.
	var sprite := spinner_root.get_node_or_null("Sprite")
	if sprite is Sprite:
		sprite.position = get_viewport().get_visible_rect().size * 0.5


func _start_async_load() -> void:
	_loader = ResourceLoader.load_interactive(target_scene)
	if _loader == null:
		push_error("SceneTransitionArea: failed to start loading '%s' — falling back to direct change_scene" % target_scene)
		get_tree().change_scene(target_scene)
		return
	_loading = true


func _process(_delta: float) -> void:
	if not _loading or _loader == null:
		return
	# Poll the loader for at most load_time_budget_ms this frame, then yield so
	# the spinner's AnimationPlayer can advance and the frame can render.
	var start := OS.get_ticks_msec()
	while OS.get_ticks_msec() - start < load_time_budget_ms:
		var err := _loader.poll()
		if err == ERR_FILE_EOF:
			# Finished loading — swap to the new scene.
			var packed := _loader.get_resource() as PackedScene
			_loader = null
			_loading = false
			if packed != null:
				get_tree().change_scene_to(packed)
			else:
				push_error("SceneTransitionArea: loaded resource from '%s' is not a PackedScene" % target_scene)
				get_tree().change_scene(target_scene)
			return
		if err != OK:
			push_error("SceneTransitionArea: error while loading '%s' — falling back to direct change_scene" % target_scene)
			_loader = null
			_loading = false
			get_tree().change_scene(target_scene)
			return
