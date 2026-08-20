class_name MapGenerationBaker
extends RefCounted

const OWNED_META: StringName = &"map_generator_owned"


func apply_plan(
	profile: MapGenerationProfile,
	plan: MapGenerationPlan,
	map_scene: MapGameScene3D
) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	if profile == null or plan == null or map_scene == null:
		diagnostics.append(_diagnostic(
			"map_generation_bake_input_missing",
			"baking requires a profile, a valid plan, and a MapGameScene3D",
			profile.target_scene_path if profile != null else "",
			"bake"
		))
		return diagnostics
	if not plan.is_valid():
		diagnostics.append_array(plan.diagnostics)
		return diagnostics
	return _apply_plan_3d(profile, plan, map_scene)


func _apply_plan_3d(
	profile: MapGenerationProfile,
	plan: MapGenerationPlan,
	map_scene: MapGameScene3D
) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	var world_root := map_scene.get_node_or_null(^"WorldRoot") as Node3D
	var terrain_root := map_scene.get_node_or_null(^"WorldRoot/Terrain") as Node3D
	if world_root == null or terrain_root == null:
		diagnostics.append(_diagnostic(
			"map_generation_bake_target_invalid",
			"3D target map must contain WorldRoot and WorldRoot/Terrain",
			profile.target_scene_path,
			"target_scene_path"
		))
		return diagnostics
	_remove_generated_nodes(map_scene)
	var ground_library := _build_mesh_library(
		profile.biome.terrain_modules,
		profile,
		diagnostics,
		"biome.terrain_modules"
	)
	if not diagnostics.is_empty():
		return diagnostics
	var ground_grid := _create_grid_map(
		&"GeneratedGroundGrid",
		ground_library.get("library") as MeshLibrary,
		profile,
		map_scene,
		terrain_root,
		2
	)
	var ground_item_ids: Dictionary = ground_library.get("item_ids", {})
	for cell: Vector2i in _cells(plan):
		var terrain_tag: StringName = plan.terrain_tags.get(cell, &"")
		var item_id := int(ground_item_ids.get(terrain_tag, -1))
		if item_id >= 0:
			ground_grid.set_cell_item(_grid_cell(profile, cell), item_id)
	if profile.biome.road_overlay_module != null:
		var road_modules: Array[MapGenerationModule3D] = [
			profile.biome.road_overlay_module,
		]
		var road_library := _build_mesh_library(
			road_modules,
			profile,
			diagnostics,
			"biome.road_overlay_module"
		)
		if diagnostics.is_empty():
			var road_grid := _create_grid_map(
				&"GeneratedRoadGrid",
				road_library.get("library") as MeshLibrary,
				profile,
				map_scene,
				terrain_root,
				0
			)
			var road_item_ids: Dictionary = road_library.get("item_ids", {})
			var road_item := int(road_item_ids.get(
				profile.biome.road_overlay_module.id,
				-1
			))
			for cell: Vector2i in plan.road_cells:
				road_grid.set_cell_item(
					_grid_cell(profile, cell),
					road_item,
					_grid_orientation(road_grid, _road_yaw(cell, plan))
				)
	if not profile.biome.detail_modules.is_empty():
		var detail_library := _build_mesh_library(
			profile.biome.detail_modules,
			profile,
			diagnostics,
			"biome.detail_modules"
		)
		if diagnostics.is_empty():
			var detail_grid := _create_grid_map(
				&"GeneratedDetailGrid",
				detail_library.get("library") as MeshLibrary,
				profile,
				map_scene,
				terrain_root,
				0
			)
			var detail_item_ids: Dictionary = detail_library.get("item_ids", {})
			for cell: Vector2i in plan.detail_rule_ids:
				var rule_id: StringName = plan.detail_rule_ids[cell]
				var detail_item := int(detail_item_ids.get(rule_id, -1))
				if detail_item >= 0:
					detail_grid.set_cell_item(
						_grid_cell(profile, cell),
						detail_item,
						_grid_orientation(
							detail_grid,
							_detail_yaw(plan.seed, cell)
						)
					)
	for placement: MapGenerationPropPlacement in plan.prop_placements:
		if placement.rule == null or placement.rule.scene == null:
			continue
		var instance := placement.rule.scene.instantiate() as Node3D
		if instance == null:
			diagnostics.append(_diagnostic(
				"map_generation_prop_instance_invalid",
				"3D prop scene root is not Node3D: %s" % placement.rule.id,
				profile.authoring_source_path(),
				"biome.prop_rules",
				String(placement.rule.id)
			))
			continue
		instance.name = _node_name(placement.id)
		instance.set_meta(OWNED_META, true)
		instance.set_meta(&"map_generation_key", String(placement.id))
		terrain_root.add_child(instance)
		instance.owner = map_scene
		instance.position = profile.cell_to_world(placement.cell)
		instance.rotation.y = float(placement.yaw_quarter_turns) * PI * 0.5
		_set_generated_collision_layers(instance, placement.rule.blocking)
	_add_navigation_region_3d(profile, plan, world_root, map_scene)
	_add_boundary_3d(profile, world_root, map_scene)
	_set_provenance(profile, plan, map_scene)
	return diagnostics


func _build_mesh_library(
	modules: Array[MapGenerationModule3D],
	profile: MapGenerationProfile,
	diagnostics: Array[Dictionary],
	field: String
) -> Dictionary:
	var library := MeshLibrary.new()
	var item_ids: Dictionary[StringName, int] = {}
	var ordered: Array[MapGenerationModule3D] = modules.duplicate()
	ordered.sort_custom(func(left: MapGenerationModule3D, right: MapGenerationModule3D) -> bool:
		return String(left.id) < String(right.id)
	)
	for item_id: int in ordered.size():
		var module := ordered[item_id]
		if module == null or module.scene == null:
			continue
		var instance := module.scene.instantiate() as Node3D
		if instance == null:
			diagnostics.append(_diagnostic(
				"map_generation_module_scene_invalid",
				"3D module scene root is not Node3D: %s" % module.id,
				profile.authoring_source_path(),
				field,
				String(module.id)
			))
			continue
		var mesh_instance := _find_mesh_instance(instance)
		if mesh_instance == null or mesh_instance.mesh == null:
			diagnostics.append(_diagnostic(
				"map_generation_module_mesh_missing",
				"3D module has no mesh: %s" % module.id,
				profile.authoring_source_path(),
				field,
				String(module.id)
			))
			instance.free()
			continue
		library.create_item(item_id)
		library.set_item_name(item_id, String(module.id))
		library.set_item_mesh(item_id, mesh_instance.mesh)
		var mesh_transform := _relative_transform(instance, mesh_instance)
		mesh_transform.origin.y += module.y_offset
		library.set_item_mesh_transform(item_id, mesh_transform)
		var shapes: Array = []
		_collect_collision_shapes(instance, instance, shapes, module.y_offset)
		library.set_item_shapes(item_id, shapes)
		item_ids[module.id] = item_id
		instance.free()
	return {"library": library, "item_ids": item_ids}


func _create_grid_map(
	name: StringName,
	library: MeshLibrary,
	profile: MapGenerationProfile,
	map_scene: MapGameScene3D,
	parent: Node3D,
	collision_layer: int
) -> GridMap:
	var grid := GridMap.new()
	grid.name = name
	grid.mesh_library = library
	grid.cell_size = Vector3(profile.cell_size_3d.x, 1.0, profile.cell_size_3d.y)
	grid.cell_center_x = true
	grid.cell_center_y = true
	grid.cell_center_z = true
	grid.collision_layer = collision_layer
	grid.collision_mask = 0
	grid.set_meta(OWNED_META, true)
	grid.set_meta(&"map_generation_key", String(name))
	parent.add_child(grid)
	grid.owner = map_scene
	grid.position = (
		profile.cell_to_world(profile.map_origin)
		- grid.map_to_local(Vector3i.ZERO)
	)
	return grid


func _add_navigation_region_3d(
	profile: MapGenerationProfile,
	plan: MapGenerationPlan,
	world_root: Node3D,
	map_scene: MapGameScene3D
) -> void:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.agent_radius = 0.35
	navigation_mesh.agent_height = 2.05
	var vertices := PackedVector3Array()
	var vertex_ids: Dictionary[Vector2i, int] = {}
	var polygons: Array[PackedInt32Array] = []
	for cell: Vector2i in _cells(plan):
		if not plan.walkable_cells.get(cell, false) or plan.blocked_cells.get(cell, false):
			continue
		var relative := cell - plan.origin
		# NavigationServer3D expects these XZ polygons clockwise from the +Y view.
		var corners: Array[Vector2i] = [
			relative + Vector2i(1, 0),
			relative + Vector2i(1, 1),
			relative + Vector2i(0, 1),
			relative,
		]
		var polygon := PackedInt32Array()
		for corner: Vector2i in corners:
			if not vertex_ids.has(corner):
				var position := _grid_corner_world(profile, corner)
				vertex_ids[corner] = vertices.size()
				vertices.append(position)
			polygon.append(vertex_ids[corner])
		polygons.append(polygon)
	navigation_mesh.vertices = vertices
	for polygon: PackedInt32Array in polygons:
		navigation_mesh.add_polygon(polygon)
	var region := NavigationRegion3D.new()
	region.name = &"NavigationRegion3D"
	region.navigation_mesh = navigation_mesh
	region.set_meta(OWNED_META, true)
	region.set_meta(&"map_generation_key", "GeneratedNavigationRegion3D")
	world_root.add_child(region)
	region.owner = map_scene


func _add_boundary_3d(
	profile: MapGenerationProfile,
	world_root: Node3D,
	map_scene: MapGameScene3D
) -> void:
	var boundary := StaticBody3D.new()
	boundary.name = &"GeneratedMapBoundary3D"
	boundary.collision_layer = 2
	boundary.collision_mask = 0
	boundary.set_meta(OWNED_META, true)
	boundary.set_meta(&"map_generation_key", "GeneratedMapBoundary3D")
	world_root.add_child(boundary)
	boundary.owner = map_scene
	var width := float(profile.map_size.x) * profile.cell_size_3d.x
	var depth := float(profile.map_size.y) * profile.cell_size_3d.y
	var thickness := 0.5
	var height := 3.0
	var edges := [
		{"position": Vector3(0.0, height * 0.5, -depth * 0.5), "size": Vector3(width, height, thickness)},
		{"position": Vector3(0.0, height * 0.5, depth * 0.5), "size": Vector3(width, height, thickness)},
		{"position": Vector3(-width * 0.5, height * 0.5, 0.0), "size": Vector3(thickness, height, depth)},
		{"position": Vector3(width * 0.5, height * 0.5, 0.0), "size": Vector3(thickness, height, depth)},
	]
	for index: int in edges.size():
		var edge: Dictionary = edges[index]
		var shape := BoxShape3D.new()
		shape.size = edge["size"]
		var collision := CollisionShape3D.new()
		collision.name = StringName("Edge%d" % index)
		collision.position = profile.world_origin_3d + edge["position"]
		collision.shape = shape
		boundary.add_child(collision)
		collision.owner = map_scene


func _set_provenance(
	profile: MapGenerationProfile,
	plan: MapGenerationPlan,
	map_scene: MapGameScene3D
) -> void:
	map_scene.set_meta(&"map_generator_version", plan.generator_version)
	map_scene.set_meta(&"map_generation_seed", plan.seed)
	map_scene.set_meta(&"map_generation_plan_hash", plan.plan_hash)
	map_scene.set_meta(&"map_generation_profile_path", profile.authoring_source_path())


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


func _collect_collision_shapes(
	root: Node3D,
	node: Node,
	result: Array,
	y_offset: float
) -> void:
	if node is CollisionShape3D:
		var collision := node as CollisionShape3D
		if collision.shape != null:
			var transform := _relative_transform(root, collision)
			transform.origin.y += y_offset
			result.append(collision.shape)
			result.append(transform)
	for child: Node in node.get_children():
		_collect_collision_shapes(root, child, result, y_offset)


func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	if node == root:
		return Transform3D.IDENTITY
	var result := node.transform
	var current := node.get_parent()
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _set_generated_collision_layers(node: Node, blocking: bool) -> void:
	if node is CollisionObject3D:
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 2 if blocking else 0
		collision_object.collision_mask = 0
	for child: Node in node.get_children():
		_set_generated_collision_layers(child, blocking)


func _grid_cell(profile: MapGenerationProfile, cell: Vector2i) -> Vector3i:
	var relative := cell - profile.map_origin
	return Vector3i(relative.x, 0, relative.y)


func _grid_orientation(grid: GridMap, quarter_turns: int) -> int:
	return grid.get_orthogonal_index_from_basis(
		Basis(Vector3.UP, float(quarter_turns) * PI * 0.5)
	)


func _road_yaw(cell: Vector2i, plan: MapGenerationPlan) -> int:
	var horizontal := plan.road_cells.has(cell + Vector2i.LEFT) or plan.road_cells.has(cell + Vector2i.RIGHT)
	var vertical := plan.road_cells.has(cell + Vector2i.UP) or plan.road_cells.has(cell + Vector2i.DOWN)
	return 1 if vertical and not horizontal else 0


func _detail_yaw(seed: int, cell: Vector2i) -> int:
	return absi(seed + cell.x * 31 + cell.y * 17) % 4


func _grid_corner_world(profile: MapGenerationProfile, corner: Vector2i) -> Vector3:
	var width := float(profile.map_size.x) * profile.cell_size_3d.x
	var depth := float(profile.map_size.y) * profile.cell_size_3d.y
	return profile.world_origin_3d + Vector3(
		-width * 0.5 + float(corner.x) * profile.cell_size_3d.x,
		0.02,
		-depth * 0.5 + float(corner.y) * profile.cell_size_3d.y
	)


func clear_generated_content(map_scene: Node) -> void:
	_remove_generated_nodes(map_scene)


func bake_atomic(profile: MapGenerationProfile, plan: MapGenerationPlan) -> Dictionary:
	# Never touch the formal scene until a temporary PackedScene reloads and validates successfully.
	var diagnostics: Array[Dictionary] = []
	if profile == null or profile.target_scene_path.is_empty():
		diagnostics.append(_diagnostic(
			"map_generation_bake_target_missing",
			"profile has no target scene path",
				profile.authoring_source_path() if profile != null else "",
			"target_scene_path"
		))
		return _result(false, profile, plan, diagnostics)
	var packed_target := ResourceLoader.load(
		profile.target_scene_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if packed_target == null:
		diagnostics.append(_diagnostic(
			"map_generation_bake_target_load_failed",
			"could not load target scene: %s" % profile.target_scene_path,
			profile.target_scene_path,
			"target_scene_path"
		))
		return _result(false, profile, plan, diagnostics)
	var map_scene := packed_target.instantiate() as MapGameScene3D
	if map_scene == null:
		diagnostics.append(_diagnostic(
			"map_generation_bake_target_type_invalid",
			"target scene root must inherit MapGameScene3D",
			profile.target_scene_path,
			"target_scene_path"
		))
		return _result(false, profile, plan, diagnostics)
	diagnostics.append_array(apply_plan(profile, plan, map_scene))
	if not diagnostics.is_empty():
		map_scene.free()
		return _result(false, profile, plan, diagnostics)
	var packed_output := PackedScene.new()
	var pack_error := packed_output.pack(map_scene)
	map_scene.free()
	if pack_error != OK:
		diagnostics.append(_diagnostic(
			"map_generation_scene_pack_failed",
			"could not pack generated map scene: %s" % error_string(pack_error),
			profile.target_scene_path,
			"bake"
		))
		return _result(false, profile, plan, diagnostics)
	var temporary_path := _temporary_path(profile.target_scene_path)
	var save_error := ResourceSaver.save(packed_output, temporary_path)
	if save_error != OK:
		diagnostics.append(_diagnostic(
			"map_generation_temporary_save_failed",
			"could not save temporary generated scene: %s" % error_string(save_error),
			temporary_path,
			"bake"
		))
		return _result(false, profile, plan, diagnostics)
	var temporary_scene := ResourceLoader.load(
		temporary_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if temporary_scene == null:
		diagnostics.append(_diagnostic(
			"map_generation_temporary_load_failed",
			"could not reload temporary generated scene",
			temporary_path,
			"bake"
		))
		_remove_file(temporary_path)
		return _result(false, profile, plan, diagnostics)
	var temporary_instance := temporary_scene.instantiate()
	diagnostics.append_array(MapGenerationValidator.new().validate_baked_scene(profile, temporary_instance))
	temporary_instance.free()
	if not diagnostics.is_empty():
		_remove_file(temporary_path)
		return _result(false, profile, plan, diagnostics)
	var replace_error := _replace_file_atomically(temporary_path, profile.target_scene_path)
	if replace_error != OK:
		diagnostics.append(_diagnostic(
			"map_generation_atomic_replace_failed",
			"could not replace target scene atomically: %s" % error_string(replace_error),
			profile.target_scene_path,
			"bake"
		))
		_remove_file(temporary_path)
		return _result(false, profile, plan, diagnostics)
	return _result(true, profile, plan, diagnostics)


func _remove_generated_nodes(root: Node) -> void:
	var generated_nodes: Array[Node] = []
	_collect_generated_nodes(root, generated_nodes)
	for node: Node in generated_nodes:
		if is_instance_valid(node) and node.get_parent() != null:
			node.get_parent().remove_child(node)
			node.free()


func _collect_generated_nodes(node: Node, result: Array[Node]) -> void:
	for child: Node in node.get_children():
		if child.get_meta(OWNED_META, false):
			result.append(child)
		else:
			_collect_generated_nodes(child, result)


func _replace_file_atomically(temporary_path: String, target_path: String) -> Error:
	# Renames stay on the project filesystem; the backup restores the target if installation fails.
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var target_absolute := ProjectSettings.globalize_path(target_path)
	var backup_absolute := target_absolute + ".mapgen.backup"
	if FileAccess.file_exists(backup_absolute):
		var stale_remove_error := DirAccess.remove_absolute(backup_absolute)
		if stale_remove_error != OK:
			return stale_remove_error
	var backup_error := DirAccess.rename_absolute(target_absolute, backup_absolute)
	if backup_error != OK:
		return backup_error
	var replace_error := DirAccess.rename_absolute(temporary_absolute, target_absolute)
	if replace_error != OK:
		DirAccess.rename_absolute(backup_absolute, target_absolute)
		return replace_error
	DirAccess.remove_absolute(backup_absolute)
	return OK


func _temporary_path(target_path: String) -> String:
	return target_path.trim_suffix(".tscn") + ".mapgen.tmp.tscn"


func _remove_file(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


func _node_name(id: StringName) -> StringName:
	return StringName(String(id).replace(".", "_").replace("-", "_").replace(":", "_"))


func _cells(plan: MapGenerationPlan) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(plan.origin.y, plan.origin.y + plan.size.y):
		for x: int in range(plan.origin.x, plan.origin.x + plan.size.x):
			result.append(Vector2i(x, y))
	return result


func _result(
	ok: bool,
	profile: MapGenerationProfile,
	plan: MapGenerationPlan,
	diagnostics: Array[Dictionary]
) -> Dictionary:
	return {
		"ok": ok,
		"target_scene": profile.target_scene_path if profile != null else "",
		"seed": plan.seed if plan != null else 0,
		"plan_hash": plan.plan_hash if plan != null else "",
		"metrics": plan.metrics if plan != null else {},
		"diagnostics": diagnostics,
	}


func _diagnostic(
	code: String,
	message: String,
	file: String,
	field: String,
	id: String = ""
) -> Dictionary:
	return {"code": code, "message": message, "file": file, "field": field, "id": id}
