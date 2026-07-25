extends Area

var played = false

func _on_Area_area_entered(_area):
	if not played:
		$SOUND.play()
		played = true
