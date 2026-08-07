# Extends Reference (not Object) so per-instance copies stored in inventory slots are
# ref-counted and freed automatically when a slot is cleared. PickupData.get_by_id()
# returns the shared registry singleton; slots must store independent copies of it
# (see PickupData.make_instance) so each item occupies its OWN slot (mice do NOT stack).
extends Reference
class_name PickupObj

var id: int = -1
var pickup_class: int = -1
var icon: String = "<none>"
var dispose_scene: String = "<none>"

func _init(id_param, pickup_class_param, icon_param, dispose_scene_param):
	self.id = id_param
	self.pickup_class = pickup_class_param
	self.icon = icon_param
	self.dispose_scene = dispose_scene_param
