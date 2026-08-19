class_name MapGenerationSceneSnapshot
extends RefCounted

const ROOT_METADATA: Array[StringName] = [
	&"map_generator_version",
	&"map_generation_seed",
	&"map_generation_plan_hash",
	&"map_generation_profile_path",
]

var generated_nodes: Array[Dictionary] = []
var root_metadata: Dictionary[StringName, Variant] = {}


static func capture(map_scene: MapGameScene3D) -> MapGenerationSceneSnapshot:
	# Packed templates avoid keeping detached rendering or physics nodes in editor undo history.
	var snapshot := MapGenerationSceneSnapshot.new()
	for metadata_name: StringName in ROOT_METADATA:
		if map_scene.has_meta(metadata_name):
			snapshot.root_metadata[metadata_name] = map_scene.get_meta(metadata_name)
	snapshot._capture_generated_nodes(map_scene, map_scene)
	return snapshot


func restore(map_scene: MapGameScene3D) -> void:
	var baker := MapGenerationBaker.new()
	baker.clear_generated_content(map_scene)
	for metadata_name: StringName in ROOT_METADATA:
		if root_metadata.has(metadata_name):
			map_scene.set_meta(metadata_name, root_metadata[metadata_name])
		elif map_scene.has_meta(metadata_name):
			map_scene.remove_meta(metadata_name)
	for record: Dictionary in generated_nodes:
		var parent := map_scene.get_node_or_null(record.get("parent_path", NodePath()))
		var packed_template := record.get("packed_template") as PackedScene
		if parent == null or packed_template == null:
			continue
		var restored := packed_template.instantiate()
		parent.add_child(restored)
		restored.owner = map_scene


func _capture_generated_nodes(root: Node, node: Node) -> void:
	for child: Node in node.get_children():
		if child.get_meta(&"map_generator_owned", false):
			var template := child.duplicate()
			for template_child: Node in template.get_children():
				_set_owner_recursive(template_child, template)
			var packed_template := PackedScene.new()
			var pack_error := packed_template.pack(template)
			template.free()
			if pack_error != OK:
				continue
			generated_nodes.append({
				"parent_path": root.get_path_to(node),
				"packed_template": packed_template,
			})
		else:
			_capture_generated_nodes(root, child)


func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child: Node in node.get_children():
		_set_owner_recursive(child, owner)
