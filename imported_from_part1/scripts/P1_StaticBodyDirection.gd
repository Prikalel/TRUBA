# MIGRATED FROM part1/scripts/StaticBodyDirection.gd  (file -> P1_StaticBodyDirection.gd).
# class_name renamed StaticBodyDirection -> P1_StaticBodyDirection to avoid global-class clashes.
class_name P1_StaticBodyDirection

extends Area


var directions = []


func get_main_point_position() -> Vector3:
	return $Point.global_translation
