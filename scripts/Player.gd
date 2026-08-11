extends KinematicBody

const GRAVITY = -12
const MAX_SPEED = 3
const MAX_SPEED_CRAWLING = 1.5
export var JUMP_SPEED = 3
const CRAWL_ACCEL_MULTIPLIER = 3
const ACCEL = 4.5
const DEACCEL = 16
const MAX_SLOPE_ANGLE = 40
const MAX_FALLING_SPEED = 7
const HTARGET_WHILE_FALLING_DEACCEL = 3
# Maximum look-up / look-down angle (in degrees) away from the neutral horizon.
const PITCH_LIMIT = 70
# Maximum reach (metres) of the RMB pistol hitscan ray cast from the camera.
const HITSCAN_RANGE = 100.0
# Bottom-left "hold E + move" hint shown while a drag-able prop is in range or is
# being carried. Rendered by PickupHint.show_message (the same box as the pickup
# hint, just without the icon).
const DRAG_HINT_TEXT := "зажмите E и двигайтесь на WASD"

# DOWNGRADE NOTE: Godot 3.x KinematicBody has no built-in velocity member and
# move_and_slide() requires velocity as an argument, so it is stored here.
var velocity: Vector3 = Vector3.ZERO
# DOWNGRADE NOTE: Godot 3.x KinematicBody has no floor_max_angle property; it is
# passed straight into move_and_slide() instead.
var floor_max_angle: float = deg2rad(MAX_SLOPE_ANGLE)

var dir: Vector3 = Vector3()
var last_htarget: Vector3 = Vector3()
var is_dragging: bool = false
# Current pitch offset (degrees) from the helper's neutral rotation.
# 0 == looking straight at the horizon; clamped to +/- PITCH_LIMIT.
var pitch: float = 0.0
# Rotation_Helper has a -90deg X rotation baked into the scene so it stays
# upright in world space (parent Body_CollisionShape has a compensating +90deg).
# We cache that baked neutral and drive pitch on top of it, instead of clamping
# the node's raw rotation_degrees (which is offset by ~-90 at the horizon).
var _base_pitch_deg: float = 0.0

var camera: Camera
var rotation_helper: Spatial
var player_capsule: Capsule
var arm: Arm
var drag_area: Area
var inventory: Inventory
# Center-screen interaction cursor for drag-able props (see InteractionCursor.gd).
# Shown when a draggable is in range ("you can grab") or while it is carried.
var interaction_cursor: Control = null
# Bottom-left "press E to pick up <item>" hint (PickupHint.gd); built in _ready().
var _pickup_hint: Control = null
# First lootable pickup currently overlapping the DragArea, recorded by
# _update_prompts and consumed by _update_pickup_hint. Kept here so the hint stays
# in sync (and hides) even while the inventory/pause menu is open, without
# re-scanning the area a second time every frame.
var _pickup_in_range: PickupBase = null
# Pre-placed pistol view-model; hidden until a firearm is picked up.
var pistol_mesh: Spatial = null
# Eat sound played when a FOOD item is consumed from the inventory; created in
# _ready (kept out of the Player scene file to avoid hand-editing .tscn).
var _food_sound: AudioStreamPlayer2D = null

var current_dragging_object: CollisionObject = null
# Saved collision layer/mask (and RigidBody mode) of the object currently being
# carried, restored when it is dropped (see _disable/_restore_drag_collision).
var _drag_original_layer: int = 1
var _drag_original_mask: int = 1
var _drag_original_mode: int = -1
# Prompt owners (pickups / draggable props) for which the floating "E" is currently
# shown. Tracked here because Area.body_entered does not reliably fire for a
# StaticBody (the draggable cube), so prompts are driven by polling instead.
var _prompted: Dictionary = {}
# One-frame bridge: when E is released while carrying, the carried object's
# collision is restored this same frame, but Area.get_overlapping_bodies() only
# reports it on the next physics tick. Without this flag the center cursor would
# blink hidden for one frame on release before showing the open-hand "you can
# grab" icon again.
var _drag_just_released: bool = false

var mouse_sensitivity: float = 0.05

# --- Health (hearts HUD) -------------------------------------------------------
# Emitted whenever current_health changes (carries current and max). Nothing
# connects to it yet; it's there for future UI/audio hooks.
signal health_changed

# Maximum hearts the player starts every level with. Health is reset to this on
# every (re)load / scene transition because it is (re)initialised in _ready().
export var max_health: int = 6
# Whether the hearts HUD row is drawn on screen.
export var show_health: bool = true
# Seconds the GAME OVER overlay stays before the current level auto-reloads.
export var game_over_delay: float = 3.0
# Pixel size of each heart icon in the HUD.
export var heart_size: int = 48
# Pixel inset of the hearts row from the top-left screen corner.
export var health_margin: int = 16
# Pixel gap between adjacent hearts.
export var heart_separation: int = 4

# Heart textures for the top-left HUD row (preloaded as Textures at parse time).
const _HEART_FULL := preload("res://assets/textures/ui/health/health_icon.png")
const _HEART_EMPTY := preload("res://assets/textures/ui/health/empty_health_icon.png")
# GAME OVER title font (same horror font the title screen uses, scenes/test2.tscn).
const _GAME_OVER_FONT := preload("res://imported_from_part1/fonts/DuskDemon/DuskDemon.ttf")

# Current health (hearts). Set to max_health in _ready().
var current_health: int = 0
# HBoxContainer holding the heart TextureRects (null when show_health is false).
var _health_container: HBoxContainer = null
# Latched once the player has run out of hearts, so take_damage / _die are idempotent.
var _is_dead: bool = false

func _ready():
	camera = $Body_CollisionShape/Rotation_Helper/Camera
	rotation_helper = $Body_CollisionShape/Rotation_Helper
	_base_pitch_deg = rotation_helper.rotation_degrees.x
	player_capsule = $Body_CollisionShape as Capsule
	arm = $Body_CollisionShape/Rotation_Helper/Arm as Arm
	drag_area = $Body_CollisionShape/DragArea as Area
	inventory = $Inventory as Inventory
	interaction_cursor = $InteractionCursor as Control
	arm.listen_weapon_change(inventory)
	# Firearm view-models are pre-placed nodes (not spawned by the Arm), so the
	# Player itself reacts to weapon-in-hand changes to show them.
	pistol_mesh = $Body_CollisionShape/Rotation_Helper/Camera/SM_EdgeLock9TDefender_A1
	inventory.connect("weapon_in_hand_slot", self, "_on_weapon_in_hand_slot")
	# FOOD consumed from inventory -> heal 1 HP + play the eat sound.
	inventory.connect("food_consumed", self, "eat_food")
	# So HighlightOutline (and other scripts) can find the player without a hard-coded
	# node path (which varies between scenes) and without any file I/O.
	add_to_group("player")

	# Health: start each level at full and build the hearts HUD (top-left row).
	current_health = max_health
	if show_health:
		_build_health_ui()
		_refresh_hearts()
	# Eat sound node (non-positional SFX) used when a FOOD item is eaten.
	_food_sound = AudioStreamPlayer2D.new()
	_food_sound.name = "FoodSound"
	_food_sound.stream = load("res://assets/sounds/player/food.mp3")
	add_child(_food_sound)
	# Bottom-left "нажмите E чтобы подобрать <предмет>" hint (PickupHint.gd). Built
	# in code (like the hearts HUD) instead of hand-editing the Player scene file.
	_pickup_hint = preload("res://scripts/PickupHint.gd").new()
	_pickup_hint.name = "PickupHint"
	add_child(_pickup_hint)

# Reacts to weapon-in-hand changes. The Arm handles spawnable melee weapon scenes;
# the Player handles pre-placed view-models such as the pistol, shown on pickup.
func _on_weapon_in_hand_slot(hand_slot_indx: int, pickup_id: int) -> void:
	var pickup_obj = PickupData.get_by_id(pickup_id)
	if (pickup_obj != null and pickup_obj.pickup_class == PickupClass.FIREARM):
		if pistol_mesh != null:
			pistol_mesh.visible = true

func _player_not_in_inventory() -> bool:
	return not inventory.visible

func _physics_process(delta):
	if _player_not_in_inventory():
		process_input()
		_update_prompts()
	# Runs every frame (even with the inventory open) so the cursor is removed the
	# instant the menu appears instead of lingering on screen.
	_update_cursor()
	_update_pickup_hint()
	process_movement(delta)
	arm.shake(velocity)

func process_input() -> void:
	var cam_xform = camera.get_global_transform()

	is_dragging = get_is_dragging()

	if is_on_floor():
		dir = Vector3()
		var input_movement_vector: Vector2 = Vector2()
		if Input.is_action_pressed("movement_forward"):
			input_movement_vector.y += 1
		if Input.is_action_pressed("movement_backward"):
			input_movement_vector.y -= 1
		if Input.is_action_pressed("movement_left"):
			input_movement_vector.x -= 1
		if Input.is_action_pressed("movement_right"):
			input_movement_vector.x += 1
		input_movement_vector = input_movement_vector.normalized()

		if Input.is_action_just_pressed("movement_jump"):
			velocity.y = JUMP_SPEED
			player_capsule.disable_crawling()
		elif Input.is_action_just_pressed("movement_crawl"):
			player_capsule.toggle_crawling()

		dir += -cam_xform.basis.z * input_movement_vector.y
		dir += cam_xform.basis.x * input_movement_vector.x
		dir.y = 0
		dir = dir.normalized()
		$AudioStreamPlayer2D.stream_paused = not is_on_floor() or Utils.floats_equal(dir.length(), 0)
	else:
		is_dragging = false

	if not is_dragging and Input.is_action_just_pressed("interaction"):
		if inventory.find_pickup_in_area(drag_area):
			$PlayPickupTaken.play()

func process_movement(delta):
	var hvel = _get_horisontal_velocity(delta)
	velocity.x = hvel.x
	velocity.z = hvel.z

	velocity.y = clamp(velocity.y + delta * GRAVITY, -MAX_FALLING_SPEED, MAX_FALLING_SPEED)

	# DOWNGRADE NOTE: Godot 3.x move_and_slide takes velocity & up direction and
	# returns the resulting velocity (no parameter-less overload exists).
	velocity = move_and_slide(velocity, Vector3.UP, false, 4, floor_max_angle)

func _get_horisontal_velocity(delta: float) -> Vector3:
	var hvel = velocity
	hvel.y = 0

	var htarget
	if is_on_floor():
		var current_speed = MAX_SPEED if not player_capsule.get_crawling() else MAX_SPEED_CRAWLING
		htarget = dir * current_speed
	else:
		# DOWNGRADE NOTE: Godot 3.x Vector3 has no .lerp(); use linear_interpolate.
		htarget = last_htarget.linear_interpolate(Vector3.ZERO, HTARGET_WHILE_FALLING_DEACCEL * delta)
	self.last_htarget = htarget

	var accel
	if dir.dot(hvel) >= 0:
		accel = ACCEL
	else:
		accel = DEACCEL
	if player_capsule.get_crawling():
		accel *= CRAWL_ACCEL_MULTIPLIER

	return hvel.linear_interpolate(htarget, accel * delta)

func get_is_dragging() -> bool:
	if not Input.is_action_pressed("interaction") or player_capsule.get_crawling():
		if (current_dragging_object != null):
			_reparent_keep_global(current_dragging_object, owner)
			_restore_drag_collision(current_dragging_object)
			# Signal a one-frame "just dropped" bridge so the interaction cursor
			# keeps showing the open-hand icon instead of blinking out on key
			# release (crawling still forbids dragging, so don't prompt then).
			if not player_capsule.get_crawling():
				_drag_just_released = true
			current_dragging_object = null
		return false
	if (current_dragging_object == null):
		var list = drag_area.get_overlapping_bodies()
		for i in range(len(list)):
			var collision_node = (list[i] as CollisionObject)
			if collision_node != null and collision_node.has_meta("draggable"):
				var is_draggable_object: bool = collision_node.get_meta("draggable")
				if is_draggable_object:
					current_dragging_object = collision_node
					# Disable collision BEFORE reparenting so the carried object can't
					# block the player (otherwise walking into it gets you stuck).
					_disable_drag_collision(current_dragging_object)
					_reparent_keep_global(current_dragging_object, self)
					break
	return current_dragging_object != null

# While an object is carried it is parented to the player; if it kept its collision
# the player would collide with the very thing they are holding and get stuck. So we
# zero its collision layer/mask while carried and restore the originals on drop. A
# carried RigidBody is also switched to MODE_STATIC so it stops simulating (it would
# otherwise fall through the now-collisionless world instead of following the player).
func _disable_drag_collision(body: CollisionObject) -> void:
	_drag_original_layer = body.collision_layer
	_drag_original_mask = body.collision_mask
	body.collision_layer = 0
	body.collision_mask = 0
	if body is RigidBody:
		var rb = body as RigidBody
		_drag_original_mode = rb.mode
		rb.mode = RigidBody.MODE_STATIC

func _restore_drag_collision(body: CollisionObject) -> void:
	body.collision_layer = _drag_original_layer
	body.collision_mask = _drag_original_mask
	if body is RigidBody and _drag_original_mode >= 0:
		var rb = body as RigidBody
		rb.mode = _drag_original_mode
	_drag_original_mode = -1

# Drives the floating "E" prompt by polling the DragArea every physics frame instead
# of relying solely on Area.body_entered (which does not reliably fire for a
# StaticBody such as the draggable cube). Shows the prompt for every interactable
# currently overlapping the area and hides it for those that left.
func _update_prompts() -> void:
	if is_dragging:
		for owner in _prompted.keys():
			if is_instance_valid(owner):
				owner.hide_text()
		_prompted.clear()
		# Nothing is lootable while something is being carried.
		_pickup_in_range = null
		return
	var still_overlapping: Dictionary = {}
	# Re-scanned every poll, so a pickup that left range stops driving the hint.
	_pickup_in_range = null
	for body in drag_area.get_overlapping_bodies():
		var owner = _get_prompt_owner(body)
		if owner == null:
			continue
		still_overlapping[owner] = true
		if not _prompted.has(owner):
			owner.show_text(self)
			_prompted[owner] = true
		# Remember the first lootable pickup in range for the bottom-left hint.
		# Draggable props also satisfy _get_prompt_owner but have no display name,
		# so only true PickupBase instances feed the hint. Hidden pickups (e.g. ones
		# not yet revealed) are skipped - an invisible item must NOT pop the hint.
		# is_visible_in_tree() also covers a pickup whose ancestor was hidden.
		if _pickup_in_range == null and owner is PickupBase and owner.can_be_picked_up() and owner.is_visible_in_tree():
			_pickup_in_range = owner
	for owner in _prompted.keys():
		if not still_overlapping.has(owner):
			if is_instance_valid(owner):
				owner.hide_text()
			_prompted.erase(owner)

# Drives the bottom-left hint (PickupHint). Runs every physics frame (unlike
# _update_prompts, which is skipped while the inventory/pause menu is open) so the
# hint disappears the instant the menu opens and never lingers on screen.
#
# Two contents share the same box, in priority order:
#   1. A lootable + visible pickup in range -> "нажмите E чтобы подобрать <имя>"
#      (icon + name). Priority matches the E-press: pressing E grabs a pickup
#      before starting a drag.
#   2. A drag-able prop in range / being carried -> "зажмите E и двигайтесь на WASD".
# _pickup_in_range is recorded by _update_prompts (it is null while dragging).
func _update_pickup_hint() -> void:
	if _pickup_hint == null:
		return
	# Hide while the inventory/pause menu is open.
	if not _player_not_in_inventory():
		_pickup_hint.hide_hint()
		return
	# 1) Pickup hint - only for a VISIBLE pickup (hidden ones must not show).
	if _pickup_in_range != null and is_instance_valid(_pickup_in_range) and _pickup_in_range.is_visible_in_tree():
		var pickup_obj = PickupData.get_by_id(_pickup_in_range.pickup_id)
		_pickup_hint.show_hint(pickup_obj)
		return
	# 2) Drag hint: a drag-able prop is in range, OR one is currently carried.
	# current_dragging_object is checked too because a carried object's collision
	# is zeroed (see _disable_drag_collision), so _has_draggable_in_range() cannot
	# see it while it is held.
	if _has_draggable_in_range() or current_dragging_object != null:
		_pickup_hint.show_message(DRAG_HINT_TEXT)
		return
	_pickup_hint.hide_hint()

# Returns true when ANY body currently overlapping the DragArea is flagged as
# drag-able (meta "draggable" == true). This is the "player is looking at
# something they can grab" condition, independent of whether E is held. While an
# object is carried its collision layer/mask is zeroed (see
# _disable_drag_collision), so it stops overlapping the area - that is why
# _update_cursor checks current_dragging_object (carried) before this (in range).
func _has_draggable_in_range() -> bool:
	for body in drag_area.get_overlapping_bodies():
		if body is CollisionObject and body.has_meta("draggable") and body.get_meta("draggable"):
			return true
	return false

# Drives the center-screen interaction cursor for drag-able props:
#   - carrying an object          -> clenched-hand  (T_hold_interaction)
#   - drag-able object in range   -> open-hand      (T_start_hold_interaction)
#   - otherwise (incl. menu open) -> cursor hidden
#
# "Carrying" keys off current_dragging_object rather than is_dragging so the
# clenched hand stays up while airborne: is_dragging is forced false in the air,
# but the object is still parented to the player and visibly carried.
func _update_cursor() -> void:
	if interaction_cursor == null:
		return
	if not _player_not_in_inventory():
		interaction_cursor.hide_cursor()
		return
	var in_range: bool = _has_draggable_in_range()
	# Consume the release-bridge: pretend the just-dropped object is still in
	# range for this single frame so the open-hand prompt does not blink out the
	# moment E is released.
	if _drag_just_released:
		_drag_just_released = false
		in_range = true
		$StoneSound.playing = false
	if current_dragging_object != null:
		interaction_cursor.show_hold()
		if not $StoneSound.playing:
			$StoneSound.play()
	elif in_range:
		interaction_cursor.show_start()
	else:
		interaction_cursor.hide_cursor()

# DOWNGRADE NOTE: Godot 3.x has no Node.reparent(); replicate it while keeping
# the global transform (matches the Godot 4 reparent default).
func _reparent_keep_global(node: Spatial, new_parent: Node) -> void:
	var keep_transform = node.global_transform
	var prev_parent = node.get_parent()
	if prev_parent != null:
		prev_parent.remove_child(node)
	new_parent.add_child(node)
	node.global_transform = keep_transform

func item_exited_from_interact_area(thing: Spatial):
	var prompt_owner = _get_prompt_owner(thing)
	if prompt_owner != null:
		prompt_owner.hide_text()

func new_item_in_interact_area(thing: Spatial):
	var prompt_owner = _get_prompt_owner(thing)
	if prompt_owner != null:
		prompt_owner.show_text(self)

# Returns the nearest ancestor of `thing` that can show an interaction prompt:
# a PickupBase (inventory pickups such as the frying pan) OR any other node exposing
# show_text()/hide_text() (e.g. a Draggable prop like the StaticWorld cube). This is
# what makes the floating "E" appear for both pickups and draggable props.
func _get_prompt_owner(thing) -> Node:
	var node = thing
	while node != null:
		if node is PickupBase:
			return node
		if node.has_method("show_text") and node.has_method("hide_text"):
			return node
		node = node.get_parent()
	return null

func _input(event):
	if _player_not_in_inventory():
		if not is_dragging:
			if event is InputEventMouseMotion:
				self.rotate_y(deg2rad(event.relative.x * mouse_sensitivity * -1))

				# Drive vertical look (pitch) from a dedicated accumulator clamped to
				# +/- PITCH_LIMIT around the helper's neutral rotation. The previous
				# code read rotation_degrees.x back, clamped it to [-70, 70] and added
				# 90 every frame; because the helper's neutral X is ~-90, that snapped
				# and then pinned the value, so the view got stuck looking up/back and
				# could never look below the horizon.
				pitch += event.relative.y * mouse_sensitivity
				pitch = clamp(pitch, -PITCH_LIMIT, PITCH_LIMIT)
				var helper_rot = rotation_helper.rotation_degrees
				helper_rot.x = _base_pitch_deg + pitch
				rotation_helper.rotation_degrees = helper_rot
			if event is InputEventMouseButton:
				if event.is_pressed() and event.get_button_index() == BUTTON_LEFT:
					arm.use_weapon()
				if event.is_pressed() and event.get_button_index() == BUTTON_RIGHT:
					if not $Body_CollisionShape/Rotation_Helper/Camera/SM_EdgeLock9TDefender_A1/AnimationPlayer.is_playing():
						$Body_CollisionShape/Rotation_Helper/Camera/SM_EdgeLock9TDefender_A1/AnimationPlayer.play("pistolshot")
						if $Body_CollisionShape/Rotation_Helper/Camera/SM_EdgeLock9TDefender_A1.is_visible_in_tree():
							$PistolSound.play()
							# Hitscan: damage whatever the crosshair ray hits (infinite ammo).
							_fire_hitscan()


# --- Shooting ------------------------------------------------------------------
# Fires a hitscan ray straight out of the camera centre (the crosshair) on RMB.
# Whatever it hits that exposes take_damage() (e.g. the Demon enemy, 1 HP) takes 1
# damage. The player's own KinematicBody is excluded so the ray, which starts
# inside the capsule at the camera, never hits the player. Ammo is infinite, so
# this never fails to fire on lack of bullets.
func _fire_hitscan() -> void:
	var space_state := get_world().direct_space_state
	var origin := camera.global_transform.origin
	var end := origin + (-camera.global_transform.basis.z.normalized()) * HITSCAN_RANGE
	var hit = space_state.intersect_ray(origin, end, [self])
	if hit.empty():
		return
	var collider = hit.collider
	if collider != null and collider.has_method("take_damage"):
		collider.take_damage(1)


# --- Health & death ------------------------------------------------------------
# Public: removes `amount` hearts (default 1). Built so the Demon's punch
# (_process_punch in Demon.gd) can deal damage without knowing about hearts/HUD.
# Does nothing once the player is already dead.
func take_damage(amount: int = 1) -> void:
	if _is_dead or amount <= 0:
		return
	current_health = max(0, current_health - amount)
	_refresh_hearts()
	emit_signal("health_changed", current_health, max_health)
	if current_health <= 0:
		_die()


# Public: restores `amount` hearts (default 1), clamped to max_health. Used when a
# FOOD item (e.g. a looted rat) is eaten from the inventory. Clamping means a full
# health eat still consumes the item (the grid clears it before emitting) without
# overhealing - exactly the requested behaviour.
func heal(amount: int = 1) -> void:
	if amount <= 0:
		return
	current_health = min(max_health, current_health + amount)
	_refresh_hearts()
	emit_signal("health_changed", current_health, max_health)


# Eats a FOOD item from the inventory: plays the eat sound and heals 1 HP (clamped
# to max_health via heal()).
func eat_food() -> void:
	if _food_sound != null:
		_food_sound.play()
	heal(1)


# Builds the horizontal hearts row in the top-left of the screen. Each slot is a
# TextureRect sized to heart_size; the container sits on the default canvas (a
# Control child of this KinematicBody renders on the viewport canvas, exactly like
# the existing InteractionCursor), so it ignores the 3D/camera transform.
func _build_health_ui() -> void:
	_health_container = HBoxContainer.new()
	_health_container.name = "HealthUI"
	_health_container.margin_left = health_margin
	_health_container.margin_top = health_margin
	_health_container.add_constant_override("separation", heart_separation)
	for _i in range(max_health):
		var heart := TextureRect.new()
		heart.texture = _HEART_FULL
		heart.expand = true
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.rect_min_size = Vector2(heart_size, heart_size)
		_health_container.add_child(heart)
	add_child(_health_container)


# Flips each heart slot to full/empty depending on current_health.
func _refresh_hearts() -> void:
	if _health_container == null:
		return
	var index := 0
	for heart in _health_container.get_children():
		heart.texture = _HEART_FULL if index < current_health else _HEART_EMPTY
		index += 1


# Out of hearts: lock input by pausing the whole tree and show the GAME OVER
# overlay. The overlay lives on its own CanvasLayer (above the hearts HUD) with
# pause_mode PROCESS so its countdown Timer still ticks while paused.
func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_show_game_over()
	get_tree().paused = true


func _show_game_over() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GameOver"
	layer.layer = 50
	layer.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(layer)

	# Full-screen dark background (matches the title screen colour in test2.tscn).
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.035, 0.045, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.margin_left = 0.0
	bg.margin_top = 0.0
	bg.margin_right = 0.0
	bg.margin_bottom = 0.0

	# Centred "GAME OVER" title using the same horror font as the title screen.
	var label := Label.new()
	label.text = "GAME OVER"
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.margin_left = 0.0
	label.margin_top = 0.0
	label.margin_right = 0.0
	label.margin_bottom = 0.0
	var font := DynamicFont.new()
	font.font_data = _GAME_OVER_FONT
	font.size = 200
	label.add_font_override("font", font)
	label.add_color_override("font_color", Color(0.86, 0.12, 0.12, 1))
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 1))
	label.add_constant_override("shadow_offset_x", 4)
	label.add_constant_override("shadow_offset_y", 4)

	# Auto-reload the current level after game_over_delay seconds. The timer keeps
	# processing during the pause (pause_mode PROCESS) and its timeout signal fires
	# regardless of this node's own pause state.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = game_over_delay
	timer.pause_mode = Node.PAUSE_MODE_PROCESS
	timer.connect("timeout", self, "_on_game_over_timeout")
	layer.add_child(timer)
	timer.start()


func _on_game_over_timeout() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
