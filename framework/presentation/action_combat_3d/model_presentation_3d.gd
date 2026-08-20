class_name ModelPresentation3D
extends RefCounted


static func apply_outline(
	root: Node,
	width: float = 0.018,
	color: Color = Color(0.018, 0.024, 0.022, 1.0)
) -> void:
	if root == null or DisplayServer.get_name() == "headless":
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null:
			continue
		for surface: int in range(mesh.mesh.get_surface_count()):
			var active := mesh.get_active_material(surface)
			if active == null:
				continue
			var local_material := active.duplicate() as Material
			if local_material == null:
				continue
			local_material.resource_local_to_scene = true
			local_material.next_pass = _outline_material(width, color)
			mesh.set_surface_override_material(surface, local_material)


static func _outline_material(width: float, color: Color) -> StandardMaterial3D:
	var outline := StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = width
	outline.albedo_color = color
	return outline


static func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, result)
