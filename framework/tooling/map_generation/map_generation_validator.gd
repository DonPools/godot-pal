class_name MapGenerationValidator
extends RefCounted


func validate_profile(profile: MapGenerationProfile, map_scene: Node = null) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	if profile == null:
		diagnostics.append(_diagnostic(
			"map_generation_profile_missing",
			"map generation requires a profile",
			"",
			"profile"
		))
		return diagnostics
	var profile_path := profile.authoring_source_path()
	var expected_schema := 2 if profile.uses_3d_modules() else 1
	if profile.schema_version != expected_schema:
		diagnostics.append(_diagnostic(
			"map_generation_schema_unsupported",
			"target mode requires map generation schema %d, got %d"
			% [expected_schema, profile.schema_version],
			profile_path,
			"schema_version"
		))
	if profile.map_size.x <= 0 or profile.map_size.y <= 0:
		diagnostics.append(_diagnostic(
			"map_generation_size_invalid",
			"map size must be positive: %s" % profile.map_size,
			profile_path,
			"map_size"
		))
	if (
		profile.uses_3d_modules()
		and (profile.cell_size_3d.x <= 0.0 or profile.cell_size_3d.y <= 0.0)
	):
		diagnostics.append(_diagnostic(
			"map_generation_3d_cell_size_invalid",
			"3D cell size must be positive: %s" % profile.cell_size_3d,
			profile_path,
			"cell_size_3d"
		))
	if profile.target_scene_path.is_empty() or not ResourceLoader.exists(profile.target_scene_path, "PackedScene"):
		diagnostics.append(_diagnostic(
			"map_generation_target_missing",
			"target scene does not exist: %s" % profile.target_scene_path,
			profile_path,
			"target_scene_path"
		))
	if profile.biome == null:
		diagnostics.append(_diagnostic(
			"map_generation_biome_missing",
			"map generation profile has no biome",
			profile_path,
			"biome"
		))
		return diagnostics
	_validate_biome(profile, profile_path, diagnostics)
	_validate_anchors(profile, map_scene, diagnostics)
	if map_scene != null:
		_validate_target_scene(profile, map_scene, diagnostics)
	return diagnostics


func validate_plan(profile: MapGenerationProfile, plan: MapGenerationPlan) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	if profile == null or plan == null:
		diagnostics.append(_diagnostic(
			"map_generation_plan_missing",
			"map generation plan validation requires a profile and plan",
			profile.authoring_source_path() if profile != null else "",
			"plan"
		))
		return diagnostics
	var expected_cells := profile.map_size.x * profile.map_size.y
	var generated_ground_count := (
		plan.terrain_tags.size()
		if profile.uses_3d_modules()
		else plan.terrain_tiles.size()
	)
	if generated_ground_count != expected_cells:
		diagnostics.append(_diagnostic(
			"map_generation_ground_incomplete",
			"plan contains %d ground cells, expected %d" % [generated_ground_count, expected_cells],
			profile.authoring_source_path(),
			"terrain_tiles"
		))
	for road_cell: Vector2i in plan.road_cells:
		if plan.road_forbidden_cells.has(road_cell):
			diagnostics.append(_diagnostic(
				"map_generation_road_crosses_protected_anchor",
				"road crosses a non-route protected anchor at %s" % road_cell,
				profile.authoring_source_path(),
				"anchors",
				"%d,%d" % [road_cell.x, road_cell.y]
			))
	for anchor: MapGenerationAnchor in profile.anchors:
		if anchor == null or not anchor.must_be_walkable:
			continue
		var cell: Vector2i = plan.resolved_anchor_cells.get(anchor.id, anchor.fallback_cell)
		if not plan.walkable_cells.get(cell, false) or plan.blocked_cells.get(cell, false):
			diagnostics.append(_diagnostic(
				"map_generation_anchor_blocked",
				"anchor is not walkable after generation: %s at %s" % [anchor.id, cell],
				profile.authoring_source_path(),
				"anchors",
				String(anchor.id)
			))
		if anchor.connect_to_road and not plan.road_cells.has(cell):
			diagnostics.append(_diagnostic(
				"map_generation_anchor_not_on_road",
				"route anchor is not part of the generated road network: %s" % anchor.id,
				profile.authoring_source_path(),
				"anchors",
				String(anchor.id)
			))
	var connected_anchors: Array[MapGenerationAnchor] = []
	for anchor: MapGenerationAnchor in profile.anchors:
		if anchor != null and anchor.connect_to_road:
			connected_anchors.append(anchor)
	if connected_anchors.size() > 1:
		var reachable := _walkable_reachable(plan, plan.resolved_anchor_cells[connected_anchors[0].id])
		for anchor: MapGenerationAnchor in connected_anchors.slice(1):
			var cell: Vector2i = plan.resolved_anchor_cells[anchor.id]
			if not reachable.has(cell):
				diagnostics.append(_diagnostic(
					"map_generation_anchor_unreachable",
					"required road anchor is unreachable: %s" % anchor.id,
					profile.authoring_source_path(),
					"anchors",
					String(anchor.id)
				))
		for anchor: MapGenerationAnchor in profile.anchors:
			if anchor == null or not anchor.must_be_walkable:
				continue
			var anchor_cell: Vector2i = plan.resolved_anchor_cells[anchor.id]
			if not reachable.has(anchor_cell):
				diagnostics.append(_diagnostic(
					"map_generation_gameplay_anchor_unreachable",
					"gameplay anchor is unreachable from the road network: %s" % anchor.id,
					profile.authoring_source_path(),
					"anchors",
					String(anchor.id)
				))
	return diagnostics


func validate_baked_scene(profile: MapGenerationProfile, map_scene: Node) -> Array[Dictionary]:
	var diagnostics := validate_profile(profile, map_scene)
	if map_scene == null:
		return diagnostics
	if profile.uses_3d_modules():
		_validate_baked_scene_3d(profile, map_scene, diagnostics)
		for generated_node: Node in _generated_nodes(map_scene):
			if _contains_forbidden_gameplay_node(generated_node):
				diagnostics.append(_diagnostic(
					"map_generation_generated_gameplay_forbidden",
					"generator-owned node contains story gameplay: %s"
					% map_scene.get_path_to(generated_node),
					profile.target_scene_path,
					"generator_owned"
				))
		return diagnostics
	var ground_layer := map_scene.get_node_or_null(^"GroundLayer") as TileMapLayer
	var detail_layer := map_scene.get_node_or_null(^"DetailLayer") as TileMapLayer
	if ground_layer != null:
		var expected_cells := profile.map_size.x * profile.map_size.y
		if ground_layer.get_used_cells().size() != expected_cells:
			diagnostics.append(_diagnostic(
				"map_generation_baked_ground_mismatch",
				"baked ground contains %d cells, expected %d"
				% [ground_layer.get_used_cells().size(), expected_cells],
				profile.target_scene_path,
				"GroundLayer"
			))
	if detail_layer == null:
		diagnostics.append(_diagnostic(
			"map_generation_detail_layer_missing",
			"baked map is missing DetailLayer",
			profile.target_scene_path,
			"DetailLayer"
		))
	for generated_node: Node in _generated_nodes(map_scene):
		if _contains_forbidden_gameplay_node(generated_node):
			diagnostics.append(_diagnostic(
				"map_generation_generated_gameplay_forbidden",
				"generator-owned node contains Interactable or story gameplay: %s"
				% map_scene.get_path_to(generated_node),
				profile.target_scene_path,
				"generator_owned"
			))
	return diagnostics


func _validate_biome(
	profile: MapGenerationProfile,
	profile_path: String,
	diagnostics: Array[Dictionary]
) -> void:
	var biome := profile.biome
	if biome.id.is_empty():
		diagnostics.append(_diagnostic(
			"map_generation_biome_id_missing", "biome ID is empty", profile_path, "biome.id"
		))
	if not profile.uses_3d_modules() and biome.tile_set == null:
		diagnostics.append(_diagnostic(
			"map_generation_tileset_missing", "biome has no TileSet", profile_path, "biome.tile_set"
		))
		return
	if not profile.uses_3d_modules():
		_validate_tile(biome.road_tile, biome.tile_set, profile_path, "biome.road_tile", diagnostics)
		_validate_tile(
			biome.clearing_tile,
			biome.tile_set,
			profile_path,
			"biome.clearing_tile",
			diagnostics
		)
	if biome.terrain_rules.is_empty():
		diagnostics.append(_diagnostic(
			"map_generation_terrain_rules_missing",
			"biome has no terrain rules",
			profile_path,
			"biome.terrain_rules"
		))
	var ids: Dictionary[StringName, bool] = {}
	for index: int in biome.terrain_rules.size():
		var rule := biome.terrain_rules[index]
		if rule == null:
			diagnostics.append(_diagnostic(
				"map_generation_terrain_rule_missing",
				"terrain rule %d is empty" % index,
				profile_path,
				"biome.terrain_rules"
			))
			continue
		_validate_rule_id(rule.id, ids, profile_path, "biome.terrain_rules", diagnostics)
		_validate_ranges(
			[
				Vector2(rule.minimum_elevation, rule.maximum_elevation),
				Vector2(rule.minimum_moisture, rule.maximum_moisture),
				Vector2(rule.minimum_fertility, rule.maximum_fertility),
				Vector2(rule.minimum_spirit, rule.maximum_spirit),
				Vector2(rule.minimum_disturbance, rule.maximum_disturbance),
			],
			profile_path,
			"biome.terrain_rules",
			String(rule.id),
			diagnostics
		)
		if not profile.uses_3d_modules():
			_validate_tile(rule.tile, biome.tile_set, profile_path, "biome.terrain_rules", diagnostics)
	ids.clear()
	for index: int in biome.detail_rules.size():
		var detail_rule := biome.detail_rules[index]
		if detail_rule == null:
			diagnostics.append(_diagnostic(
				"map_generation_detail_rule_missing",
				"detail rule %d is empty" % index,
				profile_path,
				"biome.detail_rules"
			))
			continue
		_validate_rule_id(detail_rule.id, ids, profile_path, "biome.detail_rules", diagnostics)
		if not profile.uses_3d_modules():
			_validate_tile(
				detail_rule.tile,
				biome.tile_set,
				profile_path,
				"biome.detail_rules",
				diagnostics
			)
	ids.clear()
	for index: int in biome.prop_rules.size():
		var rule := biome.prop_rules[index]
		if rule == null:
			diagnostics.append(_diagnostic(
				"map_generation_prop_rule_missing",
				"prop rule %d is empty" % index,
				profile_path,
				"biome.prop_rules"
			))
			continue
		_validate_rule_id(rule.id, ids, profile_path, "biome.prop_rules", diagnostics)
		_validate_ranges(
			[
				Vector2(rule.minimum_elevation, rule.maximum_elevation),
				Vector2(rule.minimum_moisture, rule.maximum_moisture),
				Vector2(rule.minimum_fertility, rule.maximum_fertility),
				Vector2(rule.minimum_spirit, rule.maximum_spirit),
			],
			profile_path,
			"biome.prop_rules",
			String(rule.id),
			diagnostics
		)
		var prop_scene := rule.scene_3d if profile.uses_3d_modules() else rule.scene
		if prop_scene == null:
			diagnostics.append(_diagnostic(
				"map_generation_prop_scene_missing",
				"prop rule has no PackedScene: %s" % rule.id,
				profile_path,
				"biome.prop_rules",
				String(rule.id)
			))
			continue
		var instance := prop_scene.instantiate()
		if (
			(profile.uses_3d_modules() and not instance is Node3D)
			or (not profile.uses_3d_modules() and not instance is Node2D)
		):
			diagnostics.append(_diagnostic(
				"map_generation_prop_scene_invalid",
				"prop scene root does not match target mode: %s" % rule.id,
				profile_path,
				"biome.prop_rules",
				String(rule.id)
			))
		elif profile.uses_3d_modules():
			var mesh_instance := _find_mesh_instance_3d(instance)
			if mesh_instance == null or mesh_instance.mesh == null:
				diagnostics.append(_diagnostic(
					"map_generation_3d_prop_mesh_missing",
					"3D prop scene has no mesh: %s" % rule.id,
					profile_path,
					"biome.prop_rules",
					String(rule.id)
				))
			if rule.blocking and not _has_collision_shape_3d(instance):
				diagnostics.append(_diagnostic(
					"map_generation_3d_prop_collision_missing",
					"blocking 3D prop scene has no collision shape: %s" % rule.id,
					profile_path,
					"biome.prop_rules",
					String(rule.id)
				))
		instance.free()
	if profile.uses_3d_modules():
		_validate_3d_modules(profile, diagnostics)


func _validate_anchors(
	profile: MapGenerationProfile,
	map_scene: Node,
	diagnostics: Array[Dictionary]
) -> void:
	var ids: Dictionary[StringName, bool] = {}
	var region := Rect2i(profile.map_origin, profile.map_size)
	var ground_layer := (
		map_scene.get_node_or_null(^"GroundLayer") as TileMapLayer
		if map_scene != null and not profile.uses_3d_modules()
		else null
	)
	for index: int in profile.anchors.size():
		var anchor := profile.anchors[index]
		if anchor == null:
			diagnostics.append(_diagnostic(
				"map_generation_anchor_missing",
				"anchor %d is empty" % index,
				profile.authoring_source_path(),
				"anchors"
			))
			continue
		_validate_rule_id(anchor.id, ids, profile.authoring_source_path(), "anchors", diagnostics)
		if (
			anchor.road_entry_direction != Vector2i.ZERO
			and anchor.road_entry_direction not in [
				Vector2i.LEFT,
				Vector2i.RIGHT,
				Vector2i.UP,
				Vector2i.DOWN,
			]
		):
			diagnostics.append(_diagnostic(
				"map_generation_anchor_entry_direction_invalid",
				"road entry direction must be zero or one cardinal cell: %s" % anchor.id,
				profile.authoring_source_path(),
				"anchors",
				String(anchor.id)
			))
		var cell := anchor.fallback_cell
		if anchor.use_scene_node:
			if map_scene == null:
				continue
			var anchor_node := map_scene.get_node_or_null(anchor.node_path)
			var valid_anchor_node := (
				anchor_node is Node3D
				if profile.uses_3d_modules()
				else anchor_node is Node2D
			)
			if not valid_anchor_node:
				diagnostics.append(_diagnostic(
					"map_generation_anchor_node_missing",
					"anchor node does not exist: %s" % anchor.node_path,
					profile.authoring_source_path(),
					"anchors",
					String(anchor.id)
				))
				continue
			if profile.uses_3d_modules():
				var world_root := map_scene.get_node_or_null(^"WorldRoot") as Node3D
				if world_root != null:
					cell = profile.world_to_cell(
						_transform_relative_to_ancestor(
							anchor_node as Node3D,
							world_root
						).origin
					)
			elif ground_layer != null:
				var anchor_node_2d := anchor_node as Node2D
				cell = ground_layer.local_to_map(
					ground_layer.to_local(anchor_node_2d.global_position)
				)
		if not region.has_point(cell):
			diagnostics.append(_diagnostic(
				"map_generation_anchor_out_of_bounds",
				"anchor %s resolves outside the map: %s" % [anchor.id, cell],
				profile.authoring_source_path(),
				"anchors",
				String(anchor.id)
			))
		elif anchor.connect_to_road and not region.has_point(cell + anchor.road_entry_direction):
			diagnostics.append(_diagnostic(
				"map_generation_anchor_entry_out_of_bounds",
				"road entry cell is outside the map: %s" % anchor.id,
				profile.authoring_source_path(),
				"anchors",
				String(anchor.id)
			))


func _validate_target_scene(
	profile: MapGenerationProfile,
	map_scene: Node,
	diagnostics: Array[Dictionary]
) -> void:
	if not map_scene is MapGameScene:
		diagnostics.append(_diagnostic(
			"map_generation_target_type_invalid",
			"target scene root must inherit MapGameScene",
			profile.target_scene_path,
			"target_scene_path"
		))
	var required_paths: Array[NodePath] = []
	if profile.uses_3d_modules():
		required_paths.assign(
			[^"WorldRoot", ^"WorldRoot/Terrain", ^"WorldRoot/SpawnPoints"]
		)
	else:
		required_paths.assign(
			[^"GroundLayer", ^"DetailLayer", ^"YSortRoot", ^"SpawnPoints"]
		)
	if profile.uses_3d_modules() and not map_scene is MapGameScene3D:
		diagnostics.append(_diagnostic(
			"map_generation_target_type_invalid",
			"MODULES_3D target scene root must inherit MapGameScene3D",
			profile.target_scene_path,
			"target_scene_path"
		))
	for path: NodePath in required_paths:
		if map_scene.get_node_or_null(path) == null:
			diagnostics.append(_diagnostic(
				"map_generation_target_node_missing",
				"target map is missing required node: %s" % path,
				profile.target_scene_path,
				String(path)
				))


func _transform_relative_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	if node == ancestor:
		return Transform3D.IDENTITY
	var result := node.transform
	var current := node.get_parent()
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _validate_tile(
	tile: MapGenerationTile,
	tile_set: TileSet,
	file: String,
	field: String,
	diagnostics: Array[Dictionary]
) -> void:
	if tile == null or not tile.is_valid_for(tile_set):
		diagnostics.append(_diagnostic(
			"map_generation_tile_invalid",
			"tile reference is missing or does not exist in the TileSet",
			file,
			field
		))


func _validate_rule_id(
	id: StringName,
	ids: Dictionary[StringName, bool],
	file: String,
	field: String,
	diagnostics: Array[Dictionary]
) -> void:
	if id.is_empty() or ids.has(id):
		diagnostics.append(_diagnostic(
			"map_generation_id_invalid",
			"map generation ID is empty or repeated: %s" % id,
			file,
			field,
			String(id)
		))
	ids[id] = true


func _validate_ranges(
	ranges: Array[Vector2],
	file: String,
	field: String,
	id: String,
	diagnostics: Array[Dictionary]
) -> void:
	for value_range: Vector2 in ranges:
		if value_range.x > value_range.y:
			diagnostics.append(_diagnostic(
				"map_generation_range_invalid",
				"minimum value exceeds maximum value for %s" % id,
				file,
				field,
				id
			))
			return


func _walkable_reachable(plan: MapGenerationPlan, start: Vector2i) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	if not plan.walkable_cells.get(start, false) or plan.blocked_cells.get(start, false):
		return result
	var queue: Array[Vector2i] = [start]
	result[start] = true
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor := current + direction
			if (
				plan.contains_cell(neighbor)
				and plan.walkable_cells.get(neighbor, false)
				and not plan.blocked_cells.get(neighbor, false)
				and not result.has(neighbor)
			):
				result[neighbor] = true
				queue.append(neighbor)
	return result


func _generated_nodes(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	_collect_generated_nodes(root, result)
	return result


func _collect_generated_nodes(node: Node, result: Array[Node]) -> void:
	for child: Node in node.get_children():
		if child.get_meta(&"map_generator_owned", false):
			result.append(child)
		else:
			_collect_generated_nodes(child, result)


func _contains_forbidden_gameplay_node(node: Node) -> bool:
	if node is Interactable or node is StoryInteractable3D or node is EncounterSource3D:
		return true
	for child: Node in node.get_children():
		if _contains_forbidden_gameplay_node(child):
			return true
	return false


func _validate_3d_modules(
	profile: MapGenerationProfile,
	diagnostics: Array[Dictionary]
) -> void:
	var biome := profile.biome
	var required_terrain_tags: Dictionary[StringName, bool] = {
		biome.road_terrain_tag: true,
		biome.clearing_terrain_tag: true,
	}
	for rule: MapGenerationTerrainRule in biome.terrain_rules:
		if rule != null:
			required_terrain_tags[rule.terrain_tag] = true
	var terrain_ids := _validate_module_list(
		biome.terrain_modules_3d,
		profile,
		"biome.terrain_modules_3d",
		diagnostics,
		true
	)
	for terrain_tag: StringName in required_terrain_tags:
		if not terrain_ids.has(terrain_tag):
			diagnostics.append(_diagnostic(
				"map_generation_3d_terrain_module_missing",
				"no 3D terrain module covers tag %s" % terrain_tag,
				profile.authoring_source_path(),
				"biome.terrain_modules_3d",
				String(terrain_tag)
			))
	var detail_ids := _validate_module_list(
		biome.detail_modules_3d,
		profile,
		"biome.detail_modules_3d",
		diagnostics
	)
	for rule: MapGenerationDetailRule in biome.detail_rules:
		if rule != null and not detail_ids.has(rule.id):
			diagnostics.append(_diagnostic(
				"map_generation_3d_detail_module_missing",
				"no 3D detail module covers rule %s" % rule.id,
				profile.authoring_source_path(),
				"biome.detail_modules_3d",
				String(rule.id)
			))
	if biome.road_overlay_module_3d != null:
		var road_modules: Array[MapGenerationModule3D] = [biome.road_overlay_module_3d]
		_validate_module_list(
			road_modules,
			profile,
			"biome.road_overlay_module_3d",
			diagnostics
		)


func _validate_module_list(
	modules: Array[MapGenerationModule3D],
	profile: MapGenerationProfile,
	field: String,
	diagnostics: Array[Dictionary],
	require_collision: bool = false
) -> Dictionary[StringName, bool]:
	var ids: Dictionary[StringName, bool] = {}
	for module: MapGenerationModule3D in modules:
		if module == null or module.id.is_empty() or ids.has(module.id):
			diagnostics.append(_diagnostic(
				"map_generation_3d_module_id_invalid",
				"3D module ID is empty or repeated",
				profile.authoring_source_path(),
				field
			))
			continue
		ids[module.id] = true
		if module.scene == null:
			diagnostics.append(_diagnostic(
				"map_generation_3d_module_scene_missing",
				"3D module %s has no PackedScene" % module.id,
				profile.authoring_source_path(),
				field,
				String(module.id)
			))
			continue
		var instance := module.scene.instantiate()
		var mesh_instance := _find_mesh_instance_3d(instance)
		if not instance is Node3D or mesh_instance == null or mesh_instance.mesh == null:
			diagnostics.append(_diagnostic(
				"map_generation_3d_module_scene_invalid",
				"3D module %s must have a Node3D root and mesh" % module.id,
				profile.authoring_source_path(),
				field,
				String(module.id)
			))
		elif require_collision and not _has_collision_shape_3d(instance):
			diagnostics.append(_diagnostic(
				"map_generation_3d_module_collision_missing",
				"3D terrain module %s must have a collision shape" % module.id,
				profile.authoring_source_path(),
				field,
				String(module.id)
			))
		instance.free()
	return ids


func _find_mesh_instance_3d(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found := _find_mesh_instance_3d(child)
		if found != null:
			return found
	return null


func _has_collision_shape_3d(node: Node) -> bool:
	if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
		return true
	for child: Node in node.get_children():
		if _has_collision_shape_3d(child):
			return true
	return false


func _validate_baked_scene_3d(
	profile: MapGenerationProfile,
	map_scene: Node,
	diagnostics: Array[Dictionary]
) -> void:
	var ground_grid := map_scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedGroundGrid"
	) as GridMap
	var world_root := map_scene.get_node_or_null(^"WorldRoot") as Node3D
	var expected_cells := profile.map_size.x * profile.map_size.y
	if ground_grid == null or ground_grid.get_used_cells().size() != expected_cells:
		diagnostics.append(_diagnostic(
			"map_generation_baked_ground_mismatch",
			"3D baked ground must contain %d GridMap cells" % expected_cells,
			profile.target_scene_path,
			"WorldRoot/Terrain/GeneratedGroundGrid"
		))
	elif world_root != null:
		var grid_transform := _transform_relative_to_ancestor(ground_grid, world_root)
		var first_cell_position := grid_transform * ground_grid.map_to_local(Vector3i.ZERO)
		if not first_cell_position.is_equal_approx(profile.cell_to_world(profile.map_origin)):
			diagnostics.append(_diagnostic(
				"map_generation_3d_grid_alignment_invalid",
				"3D GridMap cell centres do not match the profile world mapping",
				profile.target_scene_path,
				"WorldRoot/Terrain/GeneratedGroundGrid"
			))
	var navigation := map_scene.get_node_or_null(
		^"WorldRoot/NavigationRegion3D"
	) as NavigationRegion3D
	if (
		navigation == null
		or navigation.navigation_mesh == null
		or navigation.navigation_mesh.get_polygon_count() <= 0
	):
		diagnostics.append(_diagnostic(
			"map_generation_3d_navigation_missing",
			"3D baked map has no usable generated NavigationRegion3D",
			profile.target_scene_path,
			"WorldRoot/NavigationRegion3D"
		))
	var boundary := map_scene.get_node_or_null(
		^"WorldRoot/GeneratedMapBoundary3D"
	) as StaticBody3D
	if boundary == null or _count_collision_shapes_3d(boundary) != 4:
		diagnostics.append(_diagnostic(
			"map_generation_3d_boundary_missing",
			"3D baked map must have a generated four-edge collision boundary",
			profile.target_scene_path,
			"WorldRoot/GeneratedMapBoundary3D"
		))


func _count_collision_shapes_3d(node: Node) -> int:
	var count := 0
	if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
		count += 1
	for child: Node in node.get_children():
		count += _count_collision_shapes_3d(child)
	return count


func _diagnostic(
	code: String,
	message: String,
	file: String,
	field: String,
	id: String = ""
) -> Dictionary:
	return {"code": code, "message": message, "file": file, "field": field, "id": id}
