extends Object
class_name Utils

const FLOAT_EPSILON = 0.001

# Сравнивает float-ы.
static func floats_equal(a: float, b: float, epsilon = FLOAT_EPSILON) -> bool:
	return abs(a - b) <= epsilon

# DOWNGRADE NOTE: Godot 3.x has no is_instance_of(). The `is` operator resolves
# against a class_name literal (which is how every caller invokes this helper),
# so it is a faithful drop-in replacement.
static func get_suitable_parent(obj, searching_type):
	if obj == null:
		return null
	if obj is searching_type:
		return obj
	return get_suitable_parent(obj.get_parent(), searching_type)
