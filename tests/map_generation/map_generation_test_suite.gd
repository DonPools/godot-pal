class_name MapGenerationTestSuite
extends RefCounted

const PROFILE_PATH := "res://game/roadside/map_generation/herb_slope_profile.tres"
const TEMP_SCENE_PATH := "res://tests/.tmp_map_generation_scene.tscn"
const MANUAL_PATHS: Array[NodePath] = [
	^"SpawnPoints/safe_entry",
	^"SpawnPoints/shortcut_entry",
	^"YSortRoot/HerbWest",
	^"YSortRoot/HerbCentre",
	^"YSortRoot/HerbEast",
	^"YSortRoot/TrailBack",
]

var _failures: PackedStringArray = []


func run() -> PackedStringArray:
	_cleanup()
	var source_profile := load(PROFILE_PATH) as MapGenerationProfile
	_expect(source_profile != null, "map generation profile should load")
	if source_profile == null:
		return _failures
	var source_scene := _load_scene(source_profile.target_scene_path)
	_expect(source_scene != null, "map generation target scene should load")
	if source_scene == null:
		return _failures
	var plan := MapGenerator.new().generate(source_profile, source_scene)
	_expect(
		String(source_scene.get_meta(&"map_generation_plan_hash", "")) == plan.plan_hash,
		"formal generated map should be baked from the current profile, seed, and generator version"
	)
	source_scene.free()
	_expect(plan.is_valid(), "map generation plan should validate: %s" % [plan.diagnostics])
	_expect(plan.terrain_tiles.size() == 512, "32x16 map plan should contain exactly 512 cells")
	_expect(plan.road_cells.size() > 0, "map generation should connect required road anchors")
	_expect(
		plan.metrics.get("unreachable_walkable_cell_count", -1) == 0,
		"generated walkable space should form one reachable gameplay region"
	)
	_expect(
		(plan.metrics.get("anchor_distances", {}) as Dictionary).size() == 15,
		"six gameplay anchors should report all fifteen pairwise shortest distances"
	)
	for road_cell: Vector2i in plan.road_cells:
		_expect(
			not plan.road_forbidden_cells.has(road_cell),
			"generated roads must not cross protected resource or story anchors"
		)
	_expect(plan.prop_placements.size() > 0, "map generation should place habitat props")
	_expect(plan.detail_tiles.size() > 0, "map generation should place low-cost habitat detail tiles")
	_expect(
		plan.metrics.get("habitat_counts", {}).size() >= 4,
		"map generation should produce multiple causal habitat classes"
	)
	for blocked_cell: Vector2i in plan.blocked_cells:
		_expect(
			not plan.road_cells.has(blocked_cell) and not plan.protected_cells.has(blocked_cell),
			"blocking prop footprints must not overlap roads or protected gameplay anchors"
		)
	var repeat_scene := _load_scene(source_profile.target_scene_path)
	var repeat_plan := MapGenerator.new().generate(source_profile, repeat_scene)
	repeat_scene.free()
	_expect(
		plan.plan_hash == repeat_plan.plan_hash,
		"same profile, seed, and generator version should produce the same plan hash"
	)
	var alternate_profile := source_profile.duplicate(true) as MapGenerationProfile
	alternate_profile.seed += 1
	var alternate_scene := _load_scene(source_profile.target_scene_path)
	var alternate_plan := MapGenerator.new().generate(alternate_profile, alternate_scene)
	alternate_scene.free()
	_expect(
		alternate_plan.is_valid() and alternate_plan.plan_hash != plan.plan_hash,
		"different seeds should produce a different valid plan"
	)
	var preview_scene := _load_scene(source_profile.target_scene_path)
	var preview_snapshot := MapGenerationSceneSnapshot.capture(preview_scene)
	var preview_manual := _manual_snapshot(preview_scene)
	var preview_generated_keys := _generated_keys(preview_scene)
	var preview_ground_data := (
		preview_scene.get_node(^"GroundLayer") as TileMapLayer
	).get_tile_map_data_as_array()
	var preview_hash := String(preview_scene.get_meta(&"map_generation_plan_hash", ""))
	var preview_diagnostics := MapGenerationBaker.new().apply_plan(
		alternate_profile,
		alternate_plan,
		preview_scene
	)
	_expect(preview_diagnostics.is_empty(), "editor preview should apply a valid plan in memory")
	preview_snapshot.restore(preview_scene)
	_expect(
		_manual_snapshot(preview_scene) == preview_manual
		and (preview_scene.get_node(^"GroundLayer") as TileMapLayer).get_tile_map_data_as_array() == preview_ground_data
		and String(preview_scene.get_meta(&"map_generation_plan_hash", "")) == preview_hash,
		"Undo Preview should restore exact generated layers, manual content, and provenance"
	)
	_expect(
		_generated_keys(preview_scene) == preview_generated_keys,
		"Undo Preview should restore the exact generated prop and boundary keys"
	)
	preview_scene.free()
	if not _copy_file(source_profile.target_scene_path, TEMP_SCENE_PATH):
		_expect(false, "map generation tests should create a temporary target scene")
		return _failures
	var bake_profile := source_profile.duplicate(true) as MapGenerationProfile
	bake_profile.target_scene_path = TEMP_SCENE_PATH
	var before_scene := _load_scene(TEMP_SCENE_PATH)
	var manual_before := _manual_snapshot(before_scene)
	var bake_plan := MapGenerator.new().generate(bake_profile, before_scene)
	before_scene.free()
	var bake_result := MapGenerationBaker.new().bake_atomic(bake_profile, bake_plan)
	_expect(bool(bake_result.get("ok", false)), "temporary map bake should succeed: %s" % [bake_result])
	var after_scene := _load_scene(TEMP_SCENE_PATH)
	if after_scene != null:
		_expect(
			_manual_snapshot(after_scene) == manual_before,
			"baking should preserve manual spawns, resources, portals, bindings, and IDs"
		)
		_expect(
			(after_scene.get_node(^"GroundLayer") as TileMapLayer).get_used_cells().size() == 512,
			"baked map should serialize all generated ground cells"
		)
		_expect(
			int(after_scene.get_meta(&"map_generation_seed", 0)) == bake_plan.seed
			and String(after_scene.get_meta(&"map_generation_plan_hash", "")) == bake_plan.plan_hash,
			"baked map should record deterministic provenance without a runtime profile reference"
		)
		var baked_diagnostics := MapGenerationValidator.new().validate_baked_scene(
			bake_profile,
			after_scene
		)
		_expect(baked_diagnostics.is_empty(), "baked map should validate: %s" % [baked_diagnostics])
		after_scene.free()
	var baked_digest := _file_digest(TEMP_SCENE_PATH)
	var forbidden_rule := MapGenerationPropRule.new()
	forbidden_rule.id = &"test.forbidden_gameplay"
	forbidden_rule.scene = load(
		"res://tests/map_generation/forbidden_generated_prop.tscn"
	) as PackedScene
	var forbidden_placement := MapGenerationPropPlacement.new()
	forbidden_placement.id = &"generated.test.forbidden"
	forbidden_placement.rule = forbidden_rule
	forbidden_placement.cell = Vector2i(20, 14)
	bake_plan.prop_placements.append(forbidden_placement)
	var post_save_rejected := MapGenerationBaker.new().bake_atomic(bake_profile, bake_plan)
	_expect(
		not bool(post_save_rejected.get("ok", false))
		and _file_digest(TEMP_SCENE_PATH) == baked_digest,
		"temporary baked-scene validation failure should roll back without changing the target"
	)
	bake_plan.prop_placements.pop_back()
	var invalid_plan := MapGenerationPlan.new()
	invalid_plan.diagnostics.append({"code": "test_invalid_plan", "message": "expected failure"})
	var rejected_result := MapGenerationBaker.new().bake_atomic(bake_profile, invalid_plan)
	_expect(not bool(rejected_result.get("ok", false)), "invalid plans should be rejected before writing")
	_expect(
		_file_digest(TEMP_SCENE_PATH) == baked_digest,
		"a rejected bake should leave the target scene byte-for-byte unchanged"
	)
	_cleanup()
	return _failures


func _manual_snapshot(scene: MapGameScene) -> Dictionary:
	var result: Dictionary = {
		"entry_trigger_id": String(scene.entry_trigger_id) if scene != null else "",
	}
	if scene == null:
		return result
	for path: NodePath in MANUAL_PATHS:
		var node := scene.get_node_or_null(path) as Node2D
		if node == null:
			result[String(path)] = null
			continue
		var record: Dictionary = {
			"type": node.get_class(),
			"position": [node.position.x, node.position.y],
		}
		var interactable := node.get_node_or_null(^"Interactable") as Interactable
		if interactable != null:
			record.merge({
				"trigger_id": String(interactable.trigger_id),
				"persistent_id": String(interactable.persistent_id),
				"portal_target_map_id": String(interactable.portal_target_map_id),
				"portal_target_spawn_id": String(interactable.portal_target_spawn_id),
			})
		result[String(path)] = record
	return result


func _load_scene(path: String) -> MapGameScene:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	return packed.instantiate() as MapGameScene if packed != null else null


func _generated_keys(scene: Node) -> PackedStringArray:
	var keys := PackedStringArray()
	_collect_generated_keys(scene, keys)
	keys.sort()
	return keys


func _collect_generated_keys(node: Node, keys: PackedStringArray) -> void:
	for child: Node in node.get_children():
		if child.get_meta(&"map_generator_owned", false):
			keys.append(String(child.get_meta(&"map_generation_key", child.name)))
		else:
			_collect_generated_keys(child, keys)


func _copy_file(source_path: String, target_path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty():
		return false
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


func _file_digest(path: String) -> String:
	return FileAccess.get_sha256(path)


func _cleanup() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEMP_SCENE_PATH)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	var temporary_absolute := ProjectSettings.globalize_path(
		TEMP_SCENE_PATH.trim_suffix(".tscn") + ".mapgen.tmp.tscn"
	)
	if FileAccess.file_exists(temporary_absolute):
		DirAccess.remove_absolute(temporary_absolute)
	var backup_absolute := absolute_path + ".mapgen.backup"
	if FileAccess.file_exists(backup_absolute):
		DirAccess.remove_absolute(backup_absolute)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
