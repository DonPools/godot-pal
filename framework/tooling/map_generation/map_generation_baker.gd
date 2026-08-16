class_name MapGenerationBaker
extends RefCounted

const OWNED_META: StringName = &"map_generator_owned"


func apply_plan(
	profile: MapGenerationProfile,
	plan: MapGenerationPlan,
	map_scene: MapGameScene
) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	if profile == null or plan == null or map_scene == null:
		diagnostics.append(_diagnostic(
			"map_generation_bake_input_missing",
			"baking requires a profile, a valid plan, and a MapGameScene",
			profile.target_scene_path if profile != null else "",
			"bake"
		))
		return diagnostics
	if not plan.is_valid():
		diagnostics.append_array(plan.diagnostics)
		return diagnostics
	var ground_layer := map_scene.get_node_or_null(^"GroundLayer") as TileMapLayer
	var detail_layer := map_scene.get_node_or_null(^"DetailLayer") as TileMapLayer
	var y_sort_root := map_scene.get_node_or_null(^"YSortRoot") as Node2D
	if ground_layer == null or detail_layer == null or y_sort_root == null:
		diagnostics.append(_diagnostic(
			"map_generation_bake_target_invalid",
			"target map must contain GroundLayer, DetailLayer, and YSortRoot",
			profile.target_scene_path,
			"target_scene_path"
		))
		return diagnostics
	_remove_generated_nodes(map_scene)
	ground_layer.clear()
	detail_layer.clear()
	ground_layer.tile_set = profile.biome.tile_set
	detail_layer.tile_set = profile.biome.tile_set
	for cell: Vector2i in _cells(plan):
		var tile: MapGenerationTile = plan.terrain_tiles.get(cell)
		if tile == null:
			continue
		ground_layer.set_cell(cell, tile.source_id, tile.atlas_coords, tile.alternative_tile)
		var detail_tile: MapGenerationTile = plan.detail_tiles.get(cell)
		if detail_tile != null:
			detail_layer.set_cell(
				cell,
				detail_tile.source_id,
				detail_tile.atlas_coords,
				detail_tile.alternative_tile
			)
	for placement: MapGenerationPropPlacement in plan.prop_placements:
		if placement.rule == null or placement.rule.scene == null:
			continue
		var instance := placement.rule.scene.instantiate() as Node2D
		if instance == null:
			diagnostics.append(_diagnostic(
				"map_generation_prop_instance_invalid",
				"prop scene root is not Node2D: %s" % placement.rule.id,
				profile.authoring_source_path(),
				"biome.prop_rules",
				String(placement.rule.id)
			))
			continue
		instance.name = _node_name(placement.id)
		instance.set_meta(OWNED_META, true)
		instance.set_meta(&"map_generation_key", String(placement.id))
		y_sort_root.add_child(instance)
		instance.owner = map_scene
		instance.position = y_sort_root.to_local(
			ground_layer.to_global(ground_layer.map_to_local(placement.cell))
		)
	_add_boundary(profile, plan, ground_layer, map_scene)
	map_scene.set_meta(&"map_generator_version", plan.generator_version)
	map_scene.set_meta(&"map_generation_seed", plan.seed)
	map_scene.set_meta(&"map_generation_plan_hash", plan.plan_hash)
	map_scene.set_meta(&"map_generation_profile_path", profile.authoring_source_path())
	return diagnostics


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
	var map_scene := packed_target.instantiate() as MapGameScene
	if map_scene == null:
		diagnostics.append(_diagnostic(
			"map_generation_bake_target_type_invalid",
			"target scene root must inherit MapGameScene",
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


func _add_boundary(
	profile: MapGenerationProfile,
	plan: MapGenerationPlan,
	ground_layer: TileMapLayer,
	map_scene: MapGameScene
) -> void:
	var boundary := StaticBody2D.new()
	boundary.name = &"GeneratedMapBoundary"
	boundary.collision_layer = 2
	boundary.collision_mask = 0
	boundary.set_meta(OWNED_META, true)
	map_scene.add_child(boundary)
	boundary.owner = map_scene
	var first := plan.origin
	var last := plan.origin + plan.size - Vector2i.ONE
	var half_tile := Vector2(
		float(profile.biome.tile_set.tile_size.x) * 0.5,
		float(profile.biome.tile_set.tile_size.y) * 0.5
	)
	var vertices: Array[Vector2] = [
		ground_layer.map_to_local(first) + Vector2(0.0, -half_tile.y),
		ground_layer.map_to_local(Vector2i(last.x, first.y)) + Vector2(half_tile.x, 0.0),
		ground_layer.map_to_local(last) + Vector2(0.0, half_tile.y),
		ground_layer.map_to_local(Vector2i(first.x, last.y)) + Vector2(-half_tile.x, 0.0),
	]
	for index: int in vertices.size():
		var segment := SegmentShape2D.new()
		segment.a = vertices[index]
		segment.b = vertices[(index + 1) % vertices.size()]
		var collision := CollisionShape2D.new()
		collision.name = StringName("Edge%d" % index)
		collision.shape = segment
		boundary.add_child(collision)
		collision.owner = map_scene


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
