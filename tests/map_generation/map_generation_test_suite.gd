class_name MapGenerationTestSuite
extends RefCounted

const PROFILE_PATH := "res://game/roadside/map_generation/herb_slope_profile.tres"
const LARGE_PROFILE_PATH := "res://game/roadside/map_generation/north_slope_wilds_profile.tres"
const TEMP_SCENE_PATH := "res://tests/.tmp_map_generation_scene.tscn"
const TEMP_3D_SCENE_PATH := "res://tests/.tmp_map_generation_3d_scene.tscn"
const FIXTURE_3D_SCENE_PATH := "res://tests/map_generation/map_generation_3d_target_fixture.tscn"
const FIXTURE_3D_PROFILE_PATH := "res://tests/map_generation/map_generation_3d_profile_fixture.tres"
const FIXTURE_3D_PLAN_HASH := "42b22607d7b169815182d6c5b2fe66e22a5e61ac789b9e7418fa415f10680bdc"
const FORMAL_3D_PROFILES := {
	"res://game/roadside/map_generation/roadside_shop_3d_profile.tres": {
		"hash": "0e9feb04488181654909c0f0e76c0e8cd136f346596dbfb1f66160342982d8be",
		"cells": 252,
		"props": 10,
	},
	"res://game/roadside/map_generation/herb_slope_3d_profile.tres": {
		"hash": "7d0bcff06dd57e26b08a7a9033ba064c277659cdf38bef09bd1f5beb9ca79502",
		"cells": 512,
		"props": 30,
	},
	"res://game/roadside/map_generation/north_slope_wilds_3d_profile.tres": {
		"hash": "4f8c1619d689ae20cf7f506096ecd3e6e50825af0342610abcaf6b7911c5e7f4",
		"cells": 2048,
		"props": 92,
	},
}
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
	_test_3d_baker(null)
	_test_formal_3d_profiles()
	_cleanup()
	return _failures


func run_legacy_2d() -> PackedStringArray:
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
	_test_large_formal_profile()
	_test_3d_baker(source_profile)
	_test_formal_3d_profiles()
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


func _test_3d_baker(_source_profile: MapGenerationProfile) -> void:
	var profile := load(FIXTURE_3D_PROFILE_PATH) as MapGenerationProfile
	_expect(profile != null, "3D map generation profile fixture should load")
	if profile == null:
		return
	profile.set_authoring_source_path(FIXTURE_3D_PROFILE_PATH)
	var scene := _load_scene(FIXTURE_3D_SCENE_PATH)
	var plan := MapGenerator.new().generate(profile, scene)
	_expect(plan.is_valid(), "3D module plan should validate: %s" % [plan.diagnostics])
	_expect(
		plan.generator_version == 2
		and plan.terrain_tags.size() == 64
		and plan.metrics.get("unreachable_walkable_cell_count", -1) == 0,
		"3D plan should use generator v2 with complete reachable logical cells"
	)
	_expect(
		plan.plan_hash == FIXTURE_3D_PLAN_HASH,
		"3D generator v2 fixture should keep its reviewed golden plan hash"
	)
	_test_3d_asset_validation(profile)
	for sample: Vector2i in [Vector2i(-4, -4), Vector2i.ZERO, Vector2i(3, 3)]:
		_expect(
			profile.world_to_cell(profile.cell_to_world(sample)) == sample,
			"3D cell/world conversion should round trip %s" % sample
		)
	var manual_snapshot := _manual_3d_snapshot(scene)
	var snapshot := MapGenerationSceneSnapshot.capture(scene)
	var diagnostics := MapGenerationBaker.new().apply_plan(profile, plan, scene)
	_expect(diagnostics.is_empty(), "3D preview should apply without diagnostics: %s" % [diagnostics])
	var ground_grid := scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedGroundGrid"
	) as GridMap
	var navigation := scene.get_node_or_null(^"WorldRoot/NavigationRegion3D") as NavigationRegion3D
	_expect(
		ground_grid != null
		and ground_grid.get_used_cells().size() == 64
		and navigation != null
		and navigation.navigation_mesh.get_polygon_count() == 64 - plan.blocked_cells.size(),
		"3D preview should bake compact ground cells and deterministic navigation polygons"
	)
	if ground_grid != null:
		_expect(
			(
				ground_grid.position + ground_grid.map_to_local(Vector3i.ZERO)
			).is_equal_approx(profile.cell_to_world(profile.map_origin)),
			"3D GridMap cell centres should match the profile cell-to-world contract"
		)
	for placement: MapGenerationPropPlacement in plan.prop_placements:
		var generated_prop := _generated_node_with_key(scene, String(placement.id))
		var collision_object := _find_collision_object_3d(generated_prop)
		_expect(
			collision_object != null
			and collision_object.collision_layer == (2 if placement.rule.blocking else 0),
			"generated 3D prop collision should match its logical blocking rule: %s"
			% placement.id
		)
	_expect(
		_manual_3d_snapshot(scene) == manual_snapshot,
		"3D preview must preserve manual spawn, portal, binding, and persistent source data"
	)
	snapshot.restore(scene)
	_expect(
		scene.get_node_or_null(^"WorldRoot/Terrain/GeneratedGroundGrid") == null
		and _manual_3d_snapshot(scene) == manual_snapshot,
		"3D Undo Preview should restore generated ownership and all manual gameplay data exactly"
	)
	scene.free()
	if not _copy_file(FIXTURE_3D_SCENE_PATH, TEMP_3D_SCENE_PATH):
		_expect(false, "3D generation test should copy its temporary target")
		return
	profile.target_scene_path = TEMP_3D_SCENE_PATH
	var bake_scene := _load_scene(TEMP_3D_SCENE_PATH)
	var bake_plan := MapGenerator.new().generate(profile, bake_scene)
	bake_scene.free()
	var bake_result := MapGenerationBaker.new().bake_atomic(profile, bake_plan)
	_expect(bool(bake_result.get("ok", false)), "3D atomic bake should succeed: %s" % [bake_result])
	var baked := _load_scene(TEMP_3D_SCENE_PATH)
	if baked != null:
		_expect(
			_manual_3d_snapshot(baked) == manual_snapshot,
			"3D atomic bake should preserve manual spawn, portal, binding, and persistent source data"
		)
		var baked_diagnostics := MapGenerationValidator.new().validate_baked_scene(profile, baked)
		_expect(baked_diagnostics.is_empty(), "3D baked scene should reload and validate: %s" % [baked_diagnostics])
		baked.free()
	var baked_digest := _file_digest(TEMP_3D_SCENE_PATH)
	var forbidden_rule := MapGenerationPropRule.new()
	forbidden_rule.id = &"prop.test.forbidden_3d"
	forbidden_rule.scene_3d = load(
		"res://tests/map_generation/forbidden_generated_prop_3d.tscn"
	) as PackedScene
	var forbidden_placement := MapGenerationPropPlacement.new()
	forbidden_placement.id = &"generated.test.forbidden_3d"
	forbidden_placement.rule = forbidden_rule
	forbidden_placement.cell = Vector2i(2, 2)
	bake_plan.prop_placements.append(forbidden_placement)
	var rejected := MapGenerationBaker.new().bake_atomic(profile, bake_plan)
	_expect(
		not bool(rejected.get("ok", false))
		and _file_digest(TEMP_3D_SCENE_PATH) == baked_digest,
		"3D post-save validation failure should roll back byte-for-byte"
	)


func _manual_3d_snapshot(scene: MapGameScene) -> Dictionary:
	var spawn := scene.get_node_or_null(^"WorldRoot/SpawnPoints/default") as Marker3D
	var portal := scene.get_node_or_null(^"WorldRoot/ManualPortal") as Node3D
	var interactable := scene.get_node_or_null(
		^"WorldRoot/ManualPortal/Interactable"
	) as StoryInteractable3D
	return {
		"spawn_position": spawn.position if spawn != null else Vector3.INF,
		"portal_position": portal.position if portal != null else Vector3.INF,
		"trigger_id": String(interactable.trigger_id) if interactable != null else "",
		"persistent_id": String(interactable.persistent_id) if interactable != null else "",
		"portal_target_map_id": (
			String(interactable.portal_target_map_id) if interactable != null else ""
		),
		"portal_target_spawn_id": (
			String(interactable.portal_target_spawn_id) if interactable != null else ""
		),
	}


func _test_3d_asset_validation(profile: MapGenerationProfile) -> void:
	var detail_scene := load(
		"res://game/presentation/action_combat_3d/environment/map_generation/detail_tuft.tscn"
	) as PackedScene
	var terrain_module := profile.biome.terrain_modules_3d[0]
	var original_terrain_scene := terrain_module.scene
	terrain_module.scene = detail_scene
	var terrain_diagnostics := MapGenerationValidator.new().validate_profile(profile)
	terrain_module.scene = original_terrain_scene
	_expect(
		_diagnostics_has_code(terrain_diagnostics, "map_generation_3d_module_collision_missing"),
		"3D terrain modules without collision should fail validation"
	)
	var blocking_rule: MapGenerationPropRule
	for rule: MapGenerationPropRule in profile.biome.prop_rules:
		if rule != null and rule.blocking:
			blocking_rule = rule
			break
	var original_prop_scene := blocking_rule.scene_3d
	blocking_rule.scene_3d = detail_scene
	var prop_diagnostics := MapGenerationValidator.new().validate_profile(profile)
	blocking_rule.scene_3d = original_prop_scene
	_expect(
		_diagnostics_has_code(prop_diagnostics, "map_generation_3d_prop_collision_missing"),
		"blocking 3D props without collision should fail validation"
	)


func _diagnostics_has_code(diagnostics: Array[Dictionary], code: String) -> bool:
	for diagnostic: Dictionary in diagnostics:
		if diagnostic.get("code", "") == code:
			return true
	return false


func _generated_node_with_key(root: Node, key: String) -> Node:
	if root == null:
		return null
	if String(root.get_meta(&"map_generation_key", "")) == key:
		return root
	for child: Node in root.get_children():
		var found := _generated_node_with_key(child, key)
		if found != null:
			return found
	return null


func _find_collision_object_3d(root: Node) -> CollisionObject3D:
	if root == null:
		return null
	if root is CollisionObject3D:
		return root as CollisionObject3D
	for child: Node in root.get_children():
		var found := _find_collision_object_3d(child)
		if found != null:
			return found
	return null


func _test_large_formal_profile() -> void:
	var profile := load(LARGE_PROFILE_PATH) as MapGenerationProfile
	_expect(profile != null, "large default map profile should load")
	if profile == null:
		return
	var scene := _load_scene(profile.target_scene_path)
	_expect(scene != null, "large default map scene should load")
	if scene == null:
		return
	var plan := MapGenerator.new().generate(profile, scene)
	_expect(plan.is_valid(), "large default map plan should validate: %s" % [plan.diagnostics])
	_expect(
		plan.terrain_tiles.size() == 2048,
		"64x32 large map plan should contain exactly 2048 cells"
	)
	_expect(
		String(scene.get_meta(&"map_generation_plan_hash", "")) == plan.plan_hash,
		"large default map should be baked from its current deterministic plan"
	)
	_expect(
		plan.metrics.get("unreachable_walkable_cell_count", -1) == 0,
		"large default map should keep every walkable cell reachable"
	)
	_expect(
		plan.road_cells.size() >= 80,
		"large default map should contain a meaningful cross-map road network"
	)
	_expect(
		plan.prop_placements.size() > 60
		and plan.prop_placements.size() <= profile.maximum_generated_props,
		"large default map should contain bounded ecological prop density"
	)
	scene.free()


func _test_formal_3d_profiles() -> void:
	for profile_path: String in FORMAL_3D_PROFILES:
		var expected: Dictionary = FORMAL_3D_PROFILES[profile_path]
		var profile := load(profile_path) as MapGenerationProfile
		_expect(profile != null, "formal 3D generation profile should load: %s" % profile_path)
		if profile == null:
			continue
		var scene := _load_scene(profile.target_scene_path)
		_expect(scene is MapGameScene3D, "formal 3D profile target should use MapGameScene3D")
		if scene == null:
			continue
		var plan := MapGenerator.new().generate(profile, scene)
		_expect(plan.is_valid(), "formal 3D plan should validate: %s" % [plan.diagnostics])
		_expect(
			plan.generator_version == 2
			and plan.plan_hash == expected["hash"]
			and plan.terrain_tags.size() == expected["cells"]
			and plan.prop_placements.size() == expected["props"]
			and plan.metrics.get("unreachable_walkable_cell_count", -1) == 0,
			"formal 3D plan should match its reviewed hash, budget, and reachability: %s"
			% profile_path
		)
		_expect(
			String(scene.get_meta(&"map_generation_plan_hash", "")) == plan.plan_hash,
			"formal 3D scene should be baked from its current profile: %s" % profile_path
		)
		var diagnostics := MapGenerationValidator.new().validate_baked_scene(profile, scene)
		_expect(diagnostics.is_empty(), "formal 3D baked scene should validate: %s" % [diagnostics])
		scene.free()


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
	for path: String in [TEMP_SCENE_PATH, TEMP_3D_SCENE_PATH]:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute_path):
			DirAccess.remove_absolute(absolute_path)
		var temporary_absolute := ProjectSettings.globalize_path(
			path.trim_suffix(".tscn") + ".mapgen.tmp.tscn"
		)
		if FileAccess.file_exists(temporary_absolute):
			DirAccess.remove_absolute(temporary_absolute)
		var backup_absolute := absolute_path + ".mapgen.backup"
		if FileAccess.file_exists(backup_absolute):
			DirAccess.remove_absolute(backup_absolute)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
