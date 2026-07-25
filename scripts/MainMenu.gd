extends CanvasLayer
# Title screen overlay for the main scene (scenes/test2.tscn).
#
# Behaviour requested for the main menu:
#   * On startup it freezes the game (get_tree().paused = true) so the player
#     can't look around / swing the weapon while the title is up, and loops the
#     main-menu jingle (assets/sounds/main-menu.mp3).
#   * Clicking "Начать" simply removes the menu and lets the game run. Because
#     main-menu.mp3 is specifically the *main menu* music, it is stopped here.
#
# This CanvasLayer is configured with pause_mode = PROCESS (see test2.tscn) so
# it - and its music + button - keep working while the rest of the tree is paused.

onready var _music: AudioStreamPlayer = $MenuMusic
onready var _button: Button = $MenuControl/VBox/StartButton

func _ready() -> void:
	# Freeze gameplay until the player presses "Начать".
	get_tree().paused = true
	# The Inventory (a child of the Player) captures the mouse in its own _ready,
	# which runs before this node - so free + show the OS cursor, otherwise the
	# Start button can't be clicked on the title screen.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# main-menu.mp3 is imported with loop=true; enforce it in code too so the
	# track keeps looping even if the asset is ever re-imported without it.
	if _music.stream is AudioStreamMP3:
		_music.stream.loop = true
	_music.play()
	_button.connect("pressed", self, "_on_start_pressed")

# "если нажать на неё - просто убрать менюшку": dismiss the title screen and let
# the game run.
func _on_start_pressed() -> void:
	_music.stop()
	# Re-capture the cursor for FPS mouse-look (the Inventory expects CAPTURED).
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = false
	queue_free()
