extends Node
# Авто-генерация коллизии для геометрии уровня, импортированной из FBX.
#
# Вешается на ноду levels_merge. Проблема: levels_merge — это FBX, у которого
# в корне НЕ один MeshInstance, а вложенное дерево Spatial-ов с множеством
# MeshInstance внутри. Поэтому один StaticBody на корне (с пустой
# ConcavePolygonShape) ничего не даёт — геометрии у корня нет.
#
# Решение: при старте сцены рекурсивно обходим всех потомков, находим каждый
# MeshInstance и создаём для него отдельный StaticBody с ConcavePolygonShape
# (trimesh), запечённый прямо по его сетке (Mesh.create_trimesh_shape()).
# Так вся вложенная геометрия FBX становится твёрдой.
#
# Коллизии создаются в рантайме (в игре) и НЕ сохраняются в .tscn —
# они генерируются заново при каждой загрузке уровня.

# Печатать в консоль, сколько тел создано (для отладки).
export var verbose: bool = true


func _ready() -> void:
	var meshes: Array = []
	_collect_mesh_instances(self, meshes)

	var created := 0
	for mi in meshes:
		if _has_static_body(mi):
			continue # у этого меша уже есть тело коллизии — не дублируем

		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue

		var shape: ConcavePolygonShape = mesh.create_trimesh_shape()
		if shape == null:
			continue

		var body := StaticBody.new()
		body.name = String(mi.name) + "_col"

		var cs := CollisionShape.new()
		cs.shape = shape

		body.add_child(cs)
		mi.add_child(body)
		created += 1

	if verbose:
		print("[GenerateMeshCollision] создано trimesh-тел: %d (под '%s')" % [created, name])


# Рекурсивно собрать все MeshInstance в поддереве (любая глубина вложенности).
func _collect_mesh_instances(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is MeshInstance and not ('Stair' in c.name):
			out.append(c)
		_collect_mesh_instances(c, out)


func _has_static_body(node: Node) -> bool:
	for c in node.get_children():
		if c is StaticBody:
			return true
	return false
