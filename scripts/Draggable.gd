extends StaticBody
# A physics-immovable prop the player can stand / jump on, that can also be picked
# up and carried around by holding the interaction key ("E").
#
# - set_meta("draggable", true) is what Player.get_is_dragging() looks for when
#   deciding what to reparent onto the player while E is held.
#
# Proximity feedback is a distance-based outline (HighlightOutline) instead of a
# floating letter, so it stays visible through walls.

func _ready() -> void:
	set_meta("draggable", true)
	var outline = preload("res://scripts/HighlightOutline.gd").new()
	outline.name = "HighlightOutline"
	add_child(outline)
