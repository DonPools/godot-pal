class_name MapGenerationTestSuite
extends RefCounted

const TEMP_3D_SCENE_PATH := "res://tests/.tmp_map_generation_3d_scene.tscn"
const FIXTURE_3D_SCENE_PATH := "res://tests/map_generation/map_generation_3d_target_fixture.tscn"
const FIXTURE_3D_PROFILE_PATH := "res://tests/map_generation/map_generation_3d_profile_fixture.tres"
const FIXTURE_3D_PLAN_HASH := "ef23f5124e00922281999a56b4a1d2a19630eabd69360868c7b638dd271680d5"
const FORMAL_3D_PROFILES := {
	"res://game/roadside/map_generation/roadside_shop_3d_profile.tres": {
		"hash": "da4f7f6d8fd0fe5a7bfa6587e6a84d472522a457081ddbeb87b419432cf03915",
		"cells": 252,
		"props": 10,
	},
	"res://game/roadside/map_generation/herb_slope_3d_profile.tres": {
		"hash": "b430c6ce06cd716e64c9b97ff8a6e8d1ea1861ffedda14770cda8977b3e43fdd",
		"cells": 512,
		"props": 30,
	},
	"res://game/roadside/map_generation/north_slope_wilds_3d_profile.tres": {
		"hash": "0c84f5e1050250c8b225c441ed59431cb3843f0d1e857bf867b94c4bb3ca6939",
		"cells": 2048,
		"props": 92,
	},
}
var _failures: PackedStringArray = []


func run() -> PackedStringArray:
	_cleanup()
	_test_3d_baker()
	_test_formal_3d_profiles()
	_cleanup()
	return _failures


func _test_3d_baker() -> void:
	var profile := load(FIXTURE_3D_PROFILE_PATH) as MapGenerationProfile
	_expect(profile != null, "3D map generation profile fixture should load")
	if profile == null:
		return
	profile.set_authoring_source_path(FIXTURE_3D_PROFILE_PATH)
	var scene := _load_scene(FIXTURE_3D_SCENE_PATH)
	var plan := MapGenerator.new().generate(profile, scene)
	_expect(plan.is_valid(), "3D module plan should validate: %s" % [plan.diagnostics])
	_expect(
		plan.generator_version == 3
		and plan.terrain_tags.size() == 64
		and plan.metrics.get("unreachable_walkable_cell_count", -1) == 0,
		"3D plan should use generator v3 with complete reachable logical cells"
	)
	_expect(
		plan.plan_hash == FIXTURE_3D_PLAN_HASH,
		"3D generator v3 fixture should keep its reviewed golden plan hash"
	)
	var repeat_plan := MapGenerator.new().generate(profile, scene)
	var alternate_profile := profile.duplicate(true) as MapGenerationProfile
	alternate_profile.seed += 1
	var alternate_plan := MapGenerator.new().generate(alternate_profile, scene)
	_expect(
		repeat_plan.plan_hash == plan.plan_hash,
		"same 3D profile and seed should produce the same plan hash"
	)
	_expect(
		alternate_plan.is_valid() and alternate_plan.plan_hash != plan.plan_hash,
		"a different seed should produce a different valid 3D plan"
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
	if navigation != null and navigation.navigation_mesh.get_polygon_count() > 0:
		var navigation_polygon := navigation.navigation_mesh.get_polygon(0)
		var navigation_vertices := navigation.navigation_mesh.vertices
		var edge_one := (
			navigation_vertices[navigation_polygon[1]]
			- navigation_vertices[navigation_polygon[0]]
		)
		var edge_two := (
			navigation_vertices[navigation_polygon[2]]
			- navigation_vertices[navigation_polygon[0]]
		)
		_expect(
			edge_one.cross(edge_two).y < 0.0,
			"3D navigation polygons should use NavigationServer3D-compatible winding"
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
	forbidden_rule.scene = load(
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


func _manual_3d_snapshot(scene: MapGameScene3D) -> Dictionary:
	var spawn := scene.get_node_or_null(^"WorldRoot/SpawnPoints/default") as Marker3D
	var portal := scene.get_node_or_null(^"WorldRoot/ManualPortal") as Node3D
	var interactable := scene.get_node_or_null(
		^"WorldRoot/ManualPortal/Interactable"
	) as StoryInteractable3D
	return {
		"spawn_position": spawn.position if spawn != null else Vector3.INF,
		"portal_position": portal.position if portal != null else Vector3.INF,
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
	var terrain_module := profile.biome.terrain_modules[0]
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
	var original_prop_scene := blocking_rule.scene
	blocking_rule.scene = detail_scene
	var prop_diagnostics := MapGenerationValidator.new().validate_profile(profile)
	blocking_rule.scene = original_prop_scene
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
			plan.generator_version == 3
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


func _load_scene(path: String) -> MapGameScene3D:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	return packed.instantiate() as MapGameScene3D if packed != null else null


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
	for path: String in [TEMP_3D_SCENE_PATH]:
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
