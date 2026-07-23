extends Object
class_name WeaponObj

var id: int = -1
var hand_scene: String = "<none>"

func _init(id_param, hand_scene_param):
	self.id = id_param
	self.hand_scene = hand_scene_param
