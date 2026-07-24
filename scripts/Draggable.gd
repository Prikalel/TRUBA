extends StaticBody
# A physics-immovable prop the player can stand / jump on, that can also be picked
# up and carried around by holding the interaction key ("E").
#
# - set_meta("draggable", true) is what Player.get_is_dragging() looks for when
#   deciding what to reparent onto the player while E is held.
# - show_text()/hide_text() mirror PickupBase so the same floating "E" prompt the
#   frying-pan pickup uses appears while the player is in range. Player routes the
#   DragArea body_entered/body_exited signals to any node exposing these methods.
#
# Because this extends StaticBody (and not RigidBody) the prop is no longer driven
# by physics: it stays put, so the player can jump on top of it -- exactly what was
# needed for the StaticWorld/RigidBody3D cube in scenes/test.tscn.

# preload (not load) so FloatingPrompt is parsed at scene load, not lazily on first use.
const FloatingPromptScript := preload("res://scripts/FloatingPrompt.gd")

var _prompt = null

func _ready() -> void:
	set_meta("draggable", true)

func show_text(player_node: Spatial) -> void:
	_ensure_prompt()
	_prompt.show_prompt(player_node)

func hide_text() -> void:
	if _prompt != null:
		_prompt.hide_prompt()

func _ensure_prompt() -> void:
	if _prompt == null:
		_prompt = FloatingPromptScript.new()
		_prompt.name = "FloatingPrompt"
		add_child(_prompt)
