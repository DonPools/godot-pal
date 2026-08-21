extends SceneTree

const TEST_SAVE := "res://tests/.tmp_roadside_save.json"
const TEST_SLOTS := "res://tests/.tmp_roadside_slots"
const TEST_SETTINGS := "res://tests/.tmp_roadside_settings.cfg"
const TEST_R9_INPUT_LOG := "res://tests/.tmp_r9_input_log.jsonl"
const TEST_REALM_MIGRATION := "res://tests/.tmp_realm_migration.tres"
const TEST_MIGRATION_DIR := "res://tests/.tmp_content_migrations"
const MAP_GENERATION_TEST_SUITE := preload(
	"res://tests/map_generation/map_generation_test_suite.gd"
)
const BATTLE_SESSION_TEST_SUITE := preload(
	"res://tests/battle/battle_session_test_suite.gd"
)
const ORIGINAL_3D_ASSET_VALIDATOR := preload(
	"res://game/presentation/action_combat_3d/original_3d_asset_validator.gd"
)
const FRAMEWORK_FORBIDDEN_TOKENS: Array[String] = [
	"res://game/",
	"res://assets/original/",
	"map.roadside",
	"story.roadside",
	"item.roadside",
	"framework-lab",
]

var _failures: PackedStringArray = []
var _scene_stack_result: Variant
var _scene_stack_result_received: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_ensure_input_actions()
	_test_display_baseline()
	_test_framework_boundary()
	_test_content_database()
	_test_content_catalog_round_trip()
	_test_realm_content_migration()
	_test_original_assets()
	_test_original_3d_assets()
	_test_map_generation()
	await _test_dialogue_options()
	await _test_roadside_shop_3d_scene()
	await _test_herb_slope_3d_scene()
	await _test_north_slope_wilds_3d_scene()
	await _test_gathering_story()
	await _test_3d_gathering_flow()
	await _test_north_slope_pack_story()
	await _test_lantern_pass_story()
	await _test_battle_trigger_event()
	_test_random_state()
	_test_cultivation_rules()
	_test_equipment_transaction()
	_test_inventory_and_loadout_transactions()
	_test_item_delivery()
	_test_battle_session()
	_test_game_run_round_trip()
	_test_save_baseline_fixtures()
	_test_save_service()
	_test_settings_service()
	_test_r9_field_test_input_logger()
	_test_r9_field_test_validator()
	await _test_scene_stack()
	await _test_game_root_smoke()
	if _failures.is_empty():
		print("roadside gathering slice tests passed")
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)


func _test_display_baseline() -> void:
	var viewport_width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var viewport_height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	var window_width := int(ProjectSettings.get_setting("display/window/size/window_width_override", 0))
	var window_height := int(ProjectSettings.get_setting("display/window/size/window_height_override", 0))
	_expect(
		viewport_width == 640 and viewport_height == 360,
		"formal slice should use a 640x360 internal viewport, got %dx%d"
		% [viewport_width, viewport_height]
	)
	_expect(
		window_width == 1280 and window_height == 720,
		"default window should be an exact 2x presentation, got %dx%d"
		% [window_width, window_height]
	)
	_expect(
		ProjectSettings.get_setting("display/window/stretch/aspect") == "keep",
		"viewport presentation should preserve the 16:9 aspect ratio"
	)
	_expect(
		ProjectSettings.get_setting("display/window/stretch/mode") == "viewport",
		"world and UI should share the root viewport stretch"
	)
	_expect(
		ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer",
		"pixel presentation should use integer viewport scaling"
	)
	_expect(
		bool(ProjectSettings.get_setting("display/window/size/resizable", false)),
		"players should be able to resize the presentation window"
	)


func _test_framework_boundary() -> void:
	var paths := PackedStringArray()
	_collect_framework_files("res://framework", paths)
	_expect(not paths.is_empty(), "framework boundary check should find source files")
	for path: String in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		_expect(file != null, "framework boundary check should read %s" % path)
		if file == null:
			continue
		var source := file.get_as_text()
		file.close()
		for token: String in FRAMEWORK_FORBIDDEN_TOKENS:
			_expect(
				not source.contains(token),
				"framework file %s must not depend on game content token %s" % [path, token]
			)


func _test_content_database() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	var errors := database.build_index()
	_expect(errors.is_empty(), "original content database should validate: %s" % [errors])
	_expect(database.actors.size() == 1, "formal slice should register one original actor")
	_expect(database.realms.size() == 2, "formal slice should register two cultivation realms")
	_expect(database.foundations.size() == 2, "formal slice should register two dao foundations")
	_expect(database.npcs.size() == 2, "formal slice should register the shopkeeper and lantern keeper")
	_expect(database.maps.size() == 5, "formal slice should register gathering, combat, and lantern pass maps")
	_expect(database.items.size() == 6, "formal content should register gathering, medicine, catalyst, and build equipment")
	_expect(database.skills.size() == 3, "formal combat slice should register two base skills and one foundation ultimate")
	_expect(database.statuses.size() == 1, "formal combat slice should register one timed status")
	_expect(database.enemies.size() == 6, "formal combat content should register roadside and lantern-pass enemies")
	_expect(database.encounters.size() == 7, "formal combat content should register finite roadside and MVP encounters")
	_expect(database.shops.is_empty(), "formal slice should not keep obsolete lab shops")
	_expect(
		database.story_directories == PackedStringArray([
			"res://game/roadside/stories",
			"res://game/roadside/action_combat_3d/stories",
		]),
		"formal content should scan both roadside story directories"
	)
	var scanned := ContentSourceScanner.new().scan_story_resources(database.story_directories)
	_expect(scanned.get("diagnostics", []).is_empty(), "configured story directory should scan cleanly")
	_expect(scanned.get("stories", []).size() == 3, "formal story scan should include gathering, combat, and lantern modules")
	_expect(
		database.actor(&"actor.roadside.traveler") != null,
		"database should expose the original traveler ID"
	)
	_expect(
		database.actor(&"actor.roadside.traveler").field_model_3d != null,
		"the formal traveler definition should own its reusable 3D field model"
	)
	_expect(
		database.npc(&"npc.roadside.shopkeeper") != null
		and database.npc(&"npc.roadside.shopkeeper").field_model_3d != null,
		"database should expose the shopkeeper NPC and its reusable 3D field model"
	)
	_expect(
		database.map(&"map.roadside.shop") != null,
		"database should expose the roadside shop ID"
	)
	_expect(
		database.map(&"map.roadside.herb_slope") != null,
		"database should expose the herb slope ID"
	)
	_expect(
		database.map(&"map.roadside.north_slope_wilds") != null,
		"database should expose the large generated exploration map ID"
	)
	_expect(
		database.item(&"item.roadside.fanqing_grass") != null,
		"database should expose the gathering material ID"
	)
	_expect(
		database.map(&"map.roadside.north_slope_pack") != null
		and database.encounter(&"encounter.roadside.north_slope_pack") != null,
		"database should expose the formal 3D combat slice"
	)
	_expect(
		database.map(&"map.roadside.lantern_pass").story_module is LanternPassStory
		and database.map(&"map.roadside.north_slope_pack").story_module is NorthSlopePackStory,
		"maps with independent objectives should declare their own default StoryModule"
	)


func _test_content_catalog_round_trip() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	var catalog := ContentCatalog.new()
	catalog.build(database)
	var document := catalog.export_document()
	var qi_record := catalog.find("realm", &"realm.qi_refining")
	var sharp_record := catalog.find("foundation", &"foundation.sharp_metal")
	var medicine_record := catalog.find("item", &"item.roadside.wound_powder")
	var skill_record := catalog.find("skill", &"skill.roadside.wind_edge")
	_expect(
		qi_record.get("properties", {}).get("layer_cultivation_costs", [])
		== [20, 25, 30, 35, 40, 50, 60, 70],
		"catalog export should preserve PackedInt32Array cultivation costs"
	)
	_expect(
		String(sharp_record.get("properties", {}).get("aura_color", "")).length() == 8,
		"catalog export should encode foundation aura colors as editable RGBA"
	)
	_expect(
		medicine_record.get("properties", {}).get("icon")
		== "res://assets/original/ui/actions/potion.svg"
		and medicine_record.get("properties", {}).get("can_discard") == true
		and skill_record.get("properties", {}).get("icon")
		== "res://assets/original/ui/actions/flying_sword.svg",
		"catalog export should expose item permissions and data-driven icon paths"
	)
	var reapplied := ContentDocumentApplier.new().apply(document, catalog)
	_expect(
		reapplied.get("ok", false) and int(reapplied.get("change_count", -1)) == 0,
		"exported cultivation content should apply back without drift: %s" % [reapplied]
	)


func _test_realm_content_migration() -> void:
	_remove_if_exists(TEST_REALM_MIGRATION)
	var migration_file := TEST_MIGRATION_DIR.path_join(
		"realm_test_before_to_realm_test_after.json"
	)
	_remove_if_exists(migration_file)
	var realm := CultivationRealmDefinition.new()
	realm.id = &"realm.test_before"
	realm.display_name = "迁移测试境界"
	realm.max_layer = 1
	_expect(
		ResourceSaver.save(realm, TEST_REALM_MIGRATION) == OK,
		"realm migration fixture should save"
	)
	realm = load(TEST_REALM_MIGRATION) as CultivationRealmDefinition
	var database := ContentDatabase.new()
	database.realms.assign([realm])
	var result := ContentMigration.new().rename_id(
		"realm",
		&"realm.test_before",
		&"realm.test_after",
		database,
		TEST_MIGRATION_DIR
	)
	var migrated_text := FileAccess.get_file_as_string(TEST_REALM_MIGRATION)
	_expect(
		result.get("ok", false)
		and migrated_text.contains("realm.test_after")
		and not migrated_text.contains("realm.test_before")
		and FileAccess.file_exists(migration_file),
		"rename-id should migrate realm IDs and write an audit record: %s" % [result]
	)
	_remove_if_exists(TEST_REALM_MIGRATION)
	_remove_if_exists(migration_file)
	_remove_directory_if_empty(TEST_MIGRATION_DIR)


func _test_original_assets() -> void:
	var diagnostics := AssetLibrary.validate_assets()
	_expect(diagnostics.is_empty(), "required original assets should exist: %s" % [diagnostics])
	for path: String in AssetLibrary.REQUIRED_ASSETS:
		_expect(not path.begins_with("res://generated/"), "runtime assets must not use generated/")


func _test_original_3d_assets() -> void:
	for failure: String in ORIGINAL_3D_ASSET_VALIDATOR.validate_assets():
		_expect(false, failure)


func _test_map_generation() -> void:
	for failure: String in MAP_GENERATION_TEST_SUITE.new().run():
		_expect(false, failure)


func _test_battle_session() -> void:
	for failure: String in BATTLE_SESSION_TEST_SUITE.new().run():
		_expect(false, failure)


func _test_dialogue_options() -> void:
	var dialogue := load("res://game/roadside/stories/gathering_dialogue.tres") as DialogueDefinition
	_expect(dialogue.validate().is_empty(), "gathering dialogue options should validate")
	var invalid := dialogue.duplicate(true) as DialogueDefinition
	var duplicate_option := invalid.block(&"route_choice").options[0].duplicate(true) as DialogueOption
	invalid.block(&"route_choice").options.append(duplicate_option)
	_expect(
		not invalid.validate().is_empty(),
		"dialogue validation should reject repeated semantic option IDs"
	)
	var dock := ContentDatabaseDock.new()
	_expect(
		dock.dialogue_preview_text(dialogue).contains("[safe_route] 走旧石路"),
		"Dialogue Editor preview should expose semantic option IDs"
	)
	dock.free()
	var layer := (load("res://framework/presentation/dialogue/dialogue_layer.tscn") as PackedScene).instantiate() as DialogueLayer
	get_root().add_child(layer)
	_expect(layer.size == Vector2(640, 360), "dialogue overlay should fill the 640x360 viewport")
	_expect(
		layer.text_label.get_theme_font_size(&"font_size") == 22,
		"dialogue text should use the compact native-resolution reading size"
	)
	var holder: Dictionary = {}
	_capture_dialogue_result(layer, dialogue, &"route_choice", holder)
	await process_frame
	_expect(
		layer.is_typing()
		and not layer.wait_icon.visible
		and layer.text_label.visible_characters < layer.text_label.text.length(),
		"dialogue should type text before exposing its continue marker"
	)
	var advance := InputEventAction.new()
	advance.action = &"interact"
	advance.pressed = true
	layer._unhandled_input(advance)
	await process_frame
	_expect(
		not layer.is_typing()
		and layer.wait_icon.visible
		and not layer.is_waiting_for_option()
		and layer.text_label.visible_characters == -1,
		"the first advance input should complete the current sentence without advancing"
	)
	layer._unhandled_input(advance)
	await process_frame
	_expect(layer.is_waiting_for_option(), "dialogue should wait for a typed option")
	_expect(
		layer.option_container is VBoxContainer
		and layer.option_container.get_child_count() == 2,
		"dialogue choices should use two vertically stacked paper tabs"
	)
	var first_option := layer.option_container.get_child(0) as Button
	_expect(
		first_option != null
		and first_option.get_theme_font_size(&"font_size") == 18
		and first_option.has_focus(),
		"the first dialogue choice should expose the native-size focused style"
	)
	layer.option_selected.emit(&"safe_route")
	await process_frame
	var result := holder.get("result") as DialogueResult
	_expect(
		result != null and result.selected_option_id == &"safe_route",
		"dialogue should return the selected semantic option ID"
	)
	layer.queue_free()
	await process_frame


func _test_roadside_shop_3d_scene() -> void:
	var path := "res://game/roadside/action_combat_3d/maps/roadside_shop_3d.tscn"
	var packed := load(path) as PackedScene
	var scene := packed.instantiate() as MapGameScene3D if packed != null else null
	_expect(scene != null, "3D roadside shop should instantiate as MapGameScene3D")
	if scene == null:
		return
	get_root().add_child(scene)
	await process_frame
	var ground := scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedGroundGrid"
	) as GridMap
	var navigation := scene.get_node_or_null(
		^"WorldRoot/NavigationRegion3D"
	) as NavigationRegion3D
	var shopkeeper := scene.get_node_or_null(^"WorldRoot/Shopkeeper") as NpcCharacter3D
	var interactable := scene.get_node_or_null(
		^"WorldRoot/Shopkeeper/Interactable"
	) as StoryInteractable3D
	var wilds_portal := scene.get_node_or_null(
		^"WorldRoot/TrailToWilds/Interactable"
	) as StoryInteractable3D
	var herb_portal := scene.get_node_or_null(
		^"WorldRoot/TrailToHerbSlope/Interactable"
	) as StoryInteractable3D
	var wilds_label := scene.get_node_or_null(
		^"WorldRoot/TrailToWilds/DestinationLabel"
	) as Label3D
	var herb_label := scene.get_node_or_null(
		^"WorldRoot/TrailToHerbSlope/DestinationLabel"
	) as Label3D
	var fade_obstacle := scene.get_node_or_null(^"WorldRoot/PineTree") as Node3D
	var shopkeeper_animation: AnimationPlayer
	if shopkeeper != null:
		var npc_animation_players := shopkeeper.find_children(
			"*", "AnimationPlayer", true, false
		)
		if not npc_animation_players.is_empty():
			shopkeeper_animation = npc_animation_players[0] as AnimationPlayer
	var fade_meshes: Array[MeshInstance3D] = []
	if fade_obstacle != null:
		scene._collect_mesh_instances(fade_obstacle, fade_meshes)
	_expect(
		ground != null
		and ground.get_used_cells().size() == 252
		and navigation != null
		and navigation.navigation_mesh.get_polygon_count() > 0,
		"3D roadside shop should bake its 18x14 ground and usable navigation"
	)
	_expect(
		fade_obstacle != null
		and fade_obstacle.is_in_group(&"camera_fade_obstacle")
		and not fade_meshes.is_empty(),
		"camera-blocking trees should expose fadeable runtime meshes"
	)
	if fade_obstacle != null and not fade_meshes.is_empty():
		scene._apply_camera_obstacle_fade({fade_obstacle: true})
		_expect(
			is_equal_approx(fade_meshes[0].transparency, 0.62),
			"camera occlusion should fade a blocking environment model"
		)
		scene._restore_camera_obstacles()
		_expect(
			is_zero_approx(fade_meshes[0].transparency),
			"camera occlusion should restore transparency after the obstacle clears"
		)
	_expect(
		shopkeeper != null
		and shopkeeper.definition != null
		and shopkeeper.definition.id == &"npc.roadside.shopkeeper"
		and shopkeeper_animation != null
		and String(shopkeeper_animation.current_animation).get_file() == "idle"
		and interactable != null
		and interactable.trigger_id == &"talk_shopkeeper"
		and interactable.actor_definition_id == &"npc.roadside.shopkeeper",
		"3D shopkeeper definition, gathering trigger, and story origin actor ID should agree"
	)
	_expect(
		wilds_portal != null
		and wilds_portal.portal_target_map_id == &"map.roadside.north_slope_wilds"
		and wilds_portal.portal_target_spawn_id == &"from_shop"
		and herb_portal != null
		and herb_portal.portal_target_map_id == &"map.roadside.herb_slope"
		and herb_portal.portal_target_spawn_id == &"safe_entry"
		and scene.get_node_or_null(^"WorldRoot/SpawnPoints/from_wilds") is Marker3D
		and wilds_label != null
		and wilds_label.text == "往原野"
		and herb_label != null
		and herb_label.text == "往药草地",
		"3D shop should expose paired semantic portals to the wilds and herb slope"
	)
	if wilds_label is DestinationLabel3D:
		(wilds_label as DestinationLabel3D).set_context_suppressed(true)
		_expect(
			not wilds_label.visible,
			"a nearby interaction prompt should hide competing world plaques"
		)
		(wilds_label as DestinationLabel3D).set_context_suppressed(false)
		_expect(
			wilds_label.visible,
			"world plaques should return after the interaction prompt clears"
		)
	var from_wilds := scene.get_node(^"WorldRoot/SpawnPoints/from_wilds") as Marker3D
	var from_slope := scene.get_node(^"WorldRoot/SpawnPoints/from_slope") as Marker3D
	_expect(
		from_wilds.global_position.distance_to(wilds_portal.global_position) > 2.2
		and from_wilds.global_position.distance_to(wilds_portal.global_position) < 6.0
		and from_slope.global_position.distance_to(herb_portal.global_position) > 2.2
		and from_slope.global_position.distance_to(herb_portal.global_position) < 6.0,
		"shop exits should be visible from paired spawns without immediately retriggering"
	)
	_expect(
		String(scene.get_meta(&"map_generation_plan_hash", ""))
		== "da4f7f6d8fd0fe5a7bfa6587e6a84d472522a457081ddbeb87b419432cf03915",
		"3D roadside shop should retain its reviewed generator v3 plan hash"
	)
	var pine := scene.get_node(^"WorldRoot/PineTree") as StaticBody3D
	scene.player_3d.position = pine.position + Vector3(0.0, 0.0, 2.0)
	var collision := scene.player_3d.move_and_collide(Vector3(0.0, 0.0, -2.0))
	_expect(
		collision != null and collision.get_collider() == pine,
		"3D shop environment should physically stop player movement"
	)
	scene.queue_free()
	await process_frame


func _test_herb_slope_3d_scene() -> void:
	var path := "res://game/roadside/action_combat_3d/maps/herb_slope_3d.tscn"
	var packed := load(path) as PackedScene
	var scene := packed.instantiate() as MapGameScene3D if packed != null else null
	_expect(scene != null, "3D herb slope should instantiate as MapGameScene3D")
	if scene == null:
		return
	get_root().add_child(scene)
	await process_frame
	var ground := scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedGroundGrid"
	) as GridMap
	var detail := scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedDetailGrid"
	) as GridMap
	var navigation := scene.get_node_or_null(
		^"WorldRoot/NavigationRegion3D"
	) as NavigationRegion3D
	_expect(
		ground != null
		and ground.get_used_cells().size() == 512
		and detail != null
		and detail.get_used_cells().size() > 0
		and navigation != null
		and navigation.navigation_mesh.get_polygon_count() > 0,
		"3D herb slope should bake 32x16 terrain, habitat detail, and navigation"
	)
	_expect(
		String(scene.get_meta(&"map_generation_plan_hash", ""))
		== "b430c6ce06cd716e64c9b97ff8a6e8d1ea1861ffedda14770cda8977b3e43fdd",
		"3D herb slope should retain its reviewed generator v3 plan hash"
	)
	var patch := scene.get_node(^"WorldRoot/HerbWest") as HarvestPatch3D
	var run := GameRun.new()
	patch.configure_world_state(run, &"map.roadside.herb_slope")
	_expect(
		patch.full_visual.visible
		and not patch.cut_visual.visible
		and patch.interactable.process_mode == Node.PROCESS_MODE_INHERIT,
		"fresh 3D herb should show a complete available plant"
	)
	run.flags.set_value(RoadsideGatheringStory.FIRST_WEST)
	patch.refresh_world_state()
	_expect(
		not patch.full_visual.visible
		and patch.cut_visual.visible
		and patch.interactable.process_mode == Node.PROCESS_MODE_DISABLED,
		"leave-root harvest should show a cut unavailable 3D plant for the current trip"
	)
	run.flags.set_value(RoadsideGatheringStory.SECOND_TRIP_STARTED)
	patch.refresh_world_state()
	_expect(
		patch.full_visual.visible
		and not patch.cut_visual.visible
		and patch.interactable.process_mode == Node.PROCESS_MODE_INHERIT,
		"leave-root 3D herb should regrow when the second trip starts"
	)
	run.flags.set_value(RoadsideGatheringStory.UPROOTED_WEST)
	patch.refresh_world_state()
	_expect(
		not patch.visible and patch.process_mode == Node.PROCESS_MODE_DISABLED,
		"uprooted 3D herb should remain absent"
	)
	var portal := scene.get_node(
		^"WorldRoot/TrailBack/Interactable"
	) as StoryInteractable3D
	_expect(
		portal.portal_target_map_id == &"map.roadside.shop"
		and portal.portal_target_spawn_id == &"from_slope"
		and scene.entry_trigger_id == &"enter_herb_slope",
		"3D herb slope should preserve its semantic return portal and entry trigger"
	)
	scene.queue_free()
	await process_frame


func _test_north_slope_wilds_3d_scene() -> void:
	var path := "res://game/roadside/action_combat_3d/maps/north_slope_wilds_3d.tscn"
	var packed := load(path) as PackedScene
	var scene := packed.instantiate() as MapGameScene3D if packed != null else null
	_expect(scene != null, "3D north slope wilds should instantiate as MapGameScene3D")
	if scene == null:
		return
	get_root().add_child(scene)
	await process_frame
	var ground := scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedGroundGrid"
	) as GridMap
	var detail := scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedDetailGrid"
	) as GridMap
	var navigation := scene.get_node_or_null(
		^"WorldRoot/NavigationRegion3D"
	) as NavigationRegion3D
	var generated_prop_count := 0
	for child: Node in scene.get_node(^"WorldRoot/Terrain").get_children():
		if String(child.get_meta(&"map_generation_key", "")).begins_with("generated.prop."):
			generated_prop_count += 1
	_expect(
		ground != null
		and ground.get_used_cells().size() == 2048
		and detail != null
		and detail.get_used_cells().size() >= 80
		and generated_prop_count == 92
		and navigation != null
		and navigation.navigation_mesh.get_polygon_count() == 1923,
		"3D wilds should keep its 64x32 ecological and navigation budgets"
	)
	_expect(
		String(scene.get_meta(&"map_generation_plan_hash", ""))
		== "0c84f5e1050250c8b225c441ed59431cb3843f0d1e857bf867b94c4bb3ca6939",
		"3D wilds should retain its reviewed generator v3 plan hash"
	)
	var shop_portal := scene.get_node(
		^"WorldRoot/TrailToShop/Interactable"
	) as StoryInteractable3D
	var pack_portal := scene.get_node(
		^"WorldRoot/BeastTrailMarker/Interactable"
	) as StoryInteractable3D
	_expect(
		shop_portal.portal_target_map_id == &"map.roadside.shop"
		and shop_portal.portal_target_spawn_id == &"from_wilds"
		and pack_portal.portal_target_map_id == &"map.roadside.north_slope_pack"
		and pack_portal.portal_target_spawn_id == &"safe_entry"
		and scene.get_node_or_null(^"WorldRoot/SpawnPoints/from_shop") is Marker3D
		and scene.get_node_or_null(^"WorldRoot/SpawnPoints/from_pack") is Marker3D,
		"3D wilds should preserve both human-authored semantic portals"
	)
	_expect(
		scene.get_node_or_null(^"WorldRoot/GeneratedMapBoundary3D") is StaticBody3D
		and scene.camera_3d.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"3D wilds should use generated bounds and the fixed orthographic camera"
	)
	scene.queue_free()
	await process_frame


func _test_gathering_story() -> void:
	var story := load("res://game/roadside/stories/gathering.tres") as RoadsideGatheringStory
	var fake := FakeStoryContext.new()
	fake.dialogue_choices[&"first_offer"] = &"accept"
	fake.dialogue_choices[&"route_choice"] = &"safe_route"
	await story.run(RoadsideGatheringStory.TALK_SHOPKEEPER, fake)
	_expect(fake.stage == &"trip_one_midday", "safe route should arrive at midday")
	_expect(
		fake.recorded_pending_map == story.herb_slope
		and fake.recorded_pending_spawn_id == &"safe_entry",
		"safe route should travel to the matching slope spawn"
	)

	fake.dialogue_choices[&"harvest_choice"] = &"leave_root"
	await story.run(RoadsideGatheringStory.HARVEST_WEST, fake)
	_expect(fake.stage == &"trip_one_dusk", "first harvest should consume one time segment")
	_expect(fake.inventory_quantities.get(story.herb.id, 0) == 1, "leave-root harvest should give one herb")
	_expect(not fake.source_completed, "leave-root harvest should not permanently complete its source")
	fake.source_completed = false
	await story.run(RoadsideGatheringStory.HARVEST_CENTRE, fake)
	_expect(fake.stage == &"trip_one_late", "two safe-route harvests should return late")
	_expect(fake.inventory_quantities.get(story.herb.id, 0) == 2, "two leave-root patches should fill the delivery")

	await story.run(RoadsideGatheringStory.TALK_SHOPKEEPER, fake)
	_expect(fake.stage == &"between_trips", "first delivery should open the repeat trip")
	_expect(
		fake.delivered_items.size() == 1
		and fake.delivered_items[0].get("money_reward") == 6,
		"late first delivery should atomically pay half wages"
	)

	fake.dialogue_choices[&"second_offer"] = &"accept"
	fake.dialogue_choices[&"route_choice"] = &"shortcut"
	fake.chance_results.append(true)
	await story.run(RoadsideGatheringStory.TALK_SHOPKEEPER, fake)
	_expect(fake.stage == &"trip_two_early", "successful shortcut should preserve the early segment")
	_expect(fake.is_flag_set(RoadsideGatheringStory.SECOND_TRIP_STARTED), "second trip should be persisted")

	fake.source_completed = false
	fake.dialogue_choices[&"harvest_choice"] = &"leave_root"
	await story.run(RoadsideGatheringStory.HARVEST_WEST, fake)
	fake.source_completed = false
	fake.dialogue_choices[&"harvest_choice"] = &"uproot"
	await story.run(RoadsideGatheringStory.HARVEST_CENTRE, fake)
	_expect(fake.source_completed, "uprooting should permanently complete only the current source")
	_expect(fake.is_flag_set(RoadsideGatheringStory.UPROOTED_CENTRE), "uproot choice should persist")
	await story.run(RoadsideGatheringStory.TALK_SHOPKEEPER, fake)
	_expect(fake.stage == &"completed", "second delivery should complete the two-trip slice")
	_expect(
		fake.delivered_items.size() == 2
		and fake.delivered_items[1].get("money_reward") == 12,
		"on-time second delivery should pay full wages"
	)
	_expect(&"final_mixed" in fake.shown_blocks, "mixed harvesting should produce a concrete final observation")

	var slipped := FakeStoryContext.new()
	slipped.stage = &"between_trips"
	slipped.dialogue_choices[&"second_offer"] = &"accept"
	slipped.dialogue_choices[&"route_choice"] = &"shortcut"
	slipped.chance_results.append(false)
	await story.run(RoadsideGatheringStory.TALK_SHOPKEEPER, slipped)
	_expect(slipped.stage == &"trip_two_dusk", "failed shortcut should consume two time segments")
	_expect(&"shortcut_slip" in slipped.shown_blocks, "shortcut risk should be visible to the player")


func _test_3d_gathering_flow() -> void:
	var packed := load("res://game/bootstrap/game_root.tscn") as PackedScene
	var game_root := packed.instantiate() as GameRoot
	get_root().add_child(game_root)
	await process_frame
	game_root.start_new_game()
	await process_frame
	await process_frame
	var starting_money := game_root.game_run.economy.money
	var wilds_map := game_root.content_database.map(&"map.roadside.north_slope_wilds")
	game_root.travel_to(wilds_map, wilds_map.default_spawn_id)
	await process_frame
	await process_frame
	var wilds := game_root.scene_stack.current_scene() as MapGameScene3D
	_interact_3d(wilds, ^"WorldRoot/TrailToShop/Interactable")
	await _drive_story_ui(game_root, [])
	var shop := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		shop != null
		and shop.map_id == &"map.roadside.shop"
		and game_root.game_run.location.spawn_id == &"from_wilds",
		"3D wilds portal should enter the shop through stable map and spawn IDs"
	)
	_interact_3d(shop, ^"WorldRoot/TrailToWilds/Interactable")
	await _drive_story_ui(game_root, [])
	wilds = game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		wilds != null
		and wilds.map_id == &"map.roadside.north_slope_wilds"
		and game_root.game_run.location.spawn_id == &"from_shop",
		"shop should return to the paired wilds boundary spawn"
	)
	_interact_3d(wilds, ^"WorldRoot/BeastTrailMarker/Interactable")
	await _drive_story_ui(game_root, [])
	var pack := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		pack != null
		and pack.map_id == &"map.roadside.north_slope_pack"
		and game_root.game_run.location.spawn_id == &"safe_entry",
		"wilds should enter the combat trail through its safe boundary spawn"
	)
	_interact_3d(pack, ^"WorldRoot/ReturnMarker/Interactable")
	await _drive_story_ui(game_root, [])
	wilds = game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		wilds != null
		and wilds.map_id == &"map.roadside.north_slope_wilds"
		and game_root.game_run.location.spawn_id == &"from_pack",
		"combat trail should return to the paired wilds boundary spawn"
	)
	_interact_3d(wilds, ^"WorldRoot/TrailToShop/Interactable")
	await _drive_story_ui(game_root, [])
	shop = game_root.scene_stack.current_scene() as MapGameScene3D
	_interact_3d(shop, ^"WorldRoot/TrailToHerbSlope/Interactable")
	await _drive_story_ui(game_root, [])
	var herb_slope := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		herb_slope != null
		and herb_slope.map_id == &"map.roadside.herb_slope"
		and game_root.game_run.location.spawn_id == &"safe_entry",
		"shop should expose a physical path to the herb slope before the commission"
	)
	_interact_3d(herb_slope, ^"WorldRoot/TrailBack/Interactable")
	await _drive_story_ui(game_root, [])
	shop = game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		shop != null
		and shop.map_id == &"map.roadside.shop"
		and game_root.game_run.location.spawn_id == &"from_slope",
		"herb slope should return to the paired shop boundary spawn"
	)
	_interact_3d(shop, ^"WorldRoot/Shopkeeper/Interactable")
	await _drive_story_ui(game_root, [&"accept", &"safe_route"])
	herb_slope = game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		herb_slope != null
		and herb_slope.map_id == &"map.roadside.herb_slope"
		and game_root.game_run.story.get_stage(
			game_root.story_module.id,
			game_root.story_module.initial_stage
		) == &"trip_one_midday",
		"first 3D gathering route should arrive through the safe semantic spawn"
	)
	await _drive_story_ui(game_root, [])
	_interact_3d(herb_slope, ^"WorldRoot/HerbWest/Interactable")
	await _drive_story_ui(game_root, [&"leave_root"])
	var west_patch := herb_slope.get_node(^"WorldRoot/HerbWest") as HarvestPatch3D
	_expect(
		west_patch.cut_visual.visible and not west_patch.full_visual.visible,
		"the first leave-root choice should immediately update the 3D plant"
	)
	_interact_3d(herb_slope, ^"WorldRoot/HerbCentre/Interactable")
	await _drive_story_ui(game_root, [&"leave_root"])
	_interact_3d(herb_slope, ^"WorldRoot/TrailBack/Interactable")
	await _drive_story_ui(game_root, [])
	shop = game_root.scene_stack.current_scene() as MapGameScene3D
	_interact_3d(shop, ^"WorldRoot/Shopkeeper/Interactable")
	await _drive_story_ui(game_root, [])
	_expect(
		game_root.game_run.story.get_stage(
			game_root.story_module.id,
			game_root.story_module.initial_stage
		) == &"between_trips"
		and game_root.game_run.economy.money == starting_money + 6,
		"first late 3D delivery should atomically pay six coins and open the second trip"
	)
	_interact_3d(shop, ^"WorldRoot/Shopkeeper/Interactable")
	await _drive_story_ui(game_root, [&"accept", &"safe_route"])
	herb_slope = game_root.scene_stack.current_scene() as MapGameScene3D
	await _drive_story_ui(game_root, [])
	west_patch = herb_slope.get_node(^"WorldRoot/HerbWest") as HarvestPatch3D
	_expect(
		west_patch.full_visual.visible and west_patch.interactable.is_available(),
		"the second 3D trip should restore a leave-root plant"
	)
	_interact_3d(herb_slope, ^"WorldRoot/HerbWest/Interactable")
	await _drive_story_ui(game_root, [&"leave_root"])
	_interact_3d(herb_slope, ^"WorldRoot/HerbCentre/Interactable")
	await _drive_story_ui(game_root, [&"uproot"])
	var centre_patch := herb_slope.get_node(^"WorldRoot/HerbCentre") as HarvestPatch3D
	_expect(
		not centre_patch.visible
		and game_root.game_run.world.is_completed(
			&"map.roadside.herb_slope",
			&"herb.centre"
		),
		"uprooting should hide and persist only the selected 3D source"
	)
	_interact_3d(herb_slope, ^"WorldRoot/TrailBack/Interactable")
	await _drive_story_ui(game_root, [])
	shop = game_root.scene_stack.current_scene() as MapGameScene3D
	_interact_3d(shop, ^"WorldRoot/Shopkeeper/Interactable")
	await _drive_story_ui(game_root, [])
	var herb := game_root.content_database.item(&"item.roadside.fanqing_grass")
	_expect(
		game_root.game_run.story.get_stage(
			game_root.story_module.id,
			game_root.story_module.initial_stage
		) == &"completed"
		and game_root.game_run.inventory.quantity(herb.id) == 1
		and game_root.game_run.economy.money == starting_money + 12,
		"the complete two-trip 3D flow should preserve the uproot surplus and settle money and story state"
	)
	game_root.queue_free()
	await process_frame


func _interact_3d(scene: MapGameScene3D, path: NodePath) -> void:
	if scene == null:
		_expect(false, "3D interaction requires an active map")
		return
	var interactable := scene.get_node_or_null(path) as StoryInteractable3D
	if interactable == null:
		_expect(false, "3D interaction target should exist: %s" % path)
		return
	scene.player_3d.global_position = interactable.global_position + Vector3(1.2, 0.0, 0.0)
	scene._on_player_interact_3d()


func _drive_story_ui(game_root: GameRoot, requested_choices: Array[StringName]) -> void:
	var choices: Array[StringName] = requested_choices.duplicate()
	var idle_frames := 0
	for _frame: int in range(1200):
		if game_root.story_director.is_busy() or game_root.dialogue_layer.is_active():
			idle_frames = 0
			if game_root.dialogue_layer.is_waiting_for_option():
				if choices.is_empty():
					_expect(false, "3D story flow opened an unexpected dialogue option")
					game_root.dialogue_layer.option_selected.emit(&"later")
				else:
					game_root.dialogue_layer.option_selected.emit(choices.pop_front())
			elif game_root.dialogue_layer.is_active():
				game_root.dialogue_layer.advance_requested.emit()
		else:
			idle_frames += 1
			if idle_frames >= 3:
				_expect(choices.is_empty(), "3D story flow did not consume all requested choices")
				return
		await process_frame
	_expect(false, "3D story flow timed out")


func _test_north_slope_pack_story() -> void:
	var story := load(
		"res://game/roadside/action_combat_3d/stories/north_slope_pack.tres"
	) as NorthSlopePackStory
	var victory := FakeStoryContext.new()
	victory.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await story.run(NorthSlopePackStory.CONFRONT, victory)
	_expect(
		victory.inventory_quantities.get(story.supply_item.id, 0) == 2
		and victory.is_flag_set(NorthSlopePackStory.SUPPLY_GRANTED),
		"the first pack confrontation should grant exactly two battle supplies"
	)
	_expect(
		victory.source_completed
		and victory.stage == &"cleared"
		and &"victory" in victory.shown_blocks,
		"Victory should complete the source, advance stage, and show its result"
	)
	var escaped := FakeStoryContext.new()
	escaped.flags[NorthSlopePackStory.SUPPLY_GRANTED] = true
	escaped.next_battle_result.outcome = BattleResult.Outcome.ESCAPED
	await story.run(NorthSlopePackStory.CONFRONT, escaped)
	_expect(
		not escaped.source_completed
		and escaped.stage == &"not_started"
		and escaped.inventory_quantities.is_empty()
		and &"escaped" in escaped.shown_blocks,
		"Escaped should retain the encounter without duplicating its supply"
	)
	var defeated := FakeStoryContext.new()
	defeated.next_battle_result.outcome = BattleResult.Outcome.DEFEAT
	await story.run(NorthSlopePackStory.CONFRONT, defeated)
	_expect(
		defeated.party_restored
		and defeated.recorded_pending_map == story.defeat_map
		and defeated.recorded_pending_spawn_id == story.defeat_spawn_id
		and not defeated.source_completed,
		"Defeat should restore the party and terminal travel to the safe spawn"
	)


func _test_lantern_pass_story() -> void:
	var story := load(
		"res://game/roadside/action_combat_3d/stories/lantern_pass.tres"
	) as LanternPassStory
	_expect(story != null, "lantern pass story should load")
	var first := FakeStoryContext.new()
	first.stage = &"not_started"
	first.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await story.run(LanternPassStory.FIGHT_FIRST, first)
	_expect(
		first.source_completed and first.stage == &"first_cleared",
		"the first lantern pack should complete its source and advance stage"
	)
	var escaped := FakeStoryContext.new()
	escaped.stage = &"first_cleared"
	escaped.next_battle_result.outcome = BattleResult.Outcome.ESCAPED
	await story.run(LanternPassStory.FIGHT_SECOND, escaped)
	_expect(
		not escaped.source_completed
		and escaped.stage == &"first_cleared"
		and &"escaped" in escaped.shown_blocks,
		"an escaped lantern encounter should retain its source and stage"
	)
	var defeated := FakeStoryContext.new()
	defeated.stage = &"second_cleared"
	defeated.next_battle_result.outcome = BattleResult.Outcome.DEFEAT
	await story.run(LanternPassStory.FIGHT_THIRD, defeated)
	_expect(
		defeated.party_restored
		and defeated.recorded_pending_map == story.defeat_map
		and defeated.recorded_pending_spawn_id == story.defeat_spawn_id,
		"lantern defeat should restore the party and terminal travel to the safe spawn"
	)
	var elite := FakeStoryContext.new()
	elite.stage = &"third_cleared"
	elite.dialogue_choices[&"gear_choice"] = &"sword_seal"
	elite.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await story.run(LanternPassStory.FIGHT_ELITE, elite)
	_expect(
		elite.source_completed
		and elite.stage == &"elite_cleared"
		and elite.inventory_quantities.get(story.suppressing_sword_seal.id, 0) == 1,
		"elite Victory should atomically grant the selected build item before advancing"
	)
	var boss := FakeStoryContext.new()
	boss.stage = &"elite_cleared"
	boss.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await story.run(LanternPassStory.CONFRONT_BEAST, boss)
	_expect(
		boss.source_completed
		and boss.stage == &"boss_defeated"
		and boss.inventory_quantities.get(story.stone_heart.id, 0) == 1,
		"Boss Victory should grant exactly one breakthrough catalyst and complete its source"
	)
	var restored := FakeStoryContext.new()
	restored.stage = &"boss_defeated"
	restored.dialogue_choices[&"array_choice"] = &"restore"
	await story.run(LanternPassStory.RESOLVE_ARRAY, restored)
	_expect(
		restored.source_completed
		and restored.stage == &"restored"
		and restored.is_flag_set(LanternPassStory.ARRAY_RESTORED)
		and restored.played_sound_paths.has(story.array_restore_sound.resource_path)
		and restored.inventory_quantities.is_empty(),
		"restoring the array should open the public route without granting the core item"
	)
	var salvaged := FakeStoryContext.new()
	salvaged.stage = &"boss_defeated"
	salvaged.dialogue_choices[&"array_choice"] = &"salvage"
	await story.run(LanternPassStory.RESOLVE_ARRAY, salvaged)
	_expect(
		salvaged.source_completed
		and salvaged.stage == &"salvaged"
		and salvaged.is_flag_set(LanternPassStory.ARRAY_SALVAGED)
		and salvaged.played_sound_paths.has(story.array_salvage_sound.resource_path)
		and salvaged.inventory_quantities.get(story.lantern_core_fragment.id, 0) == 1,
		"salvaging the array should grant the core equipment before persisting the dark result"
	)
	var not_ready := FakeStoryContext.new()
	not_ready.stage = &"restored"
	not_ready.breakthrough_ready = false
	await story.run(LanternPassStory.ATTEMPT_BREAKTHROUGH, not_ready)
	_expect(
		not not_ready.source_completed
		and &"cultivation_not_ready" in not_ready.shown_blocks,
		"the altar should reject breakthrough before cultivation is full"
	)
	var breakthrough := FakeStoryContext.new()
	breakthrough.stage = &"restored"
	breakthrough.inventory_quantities[story.stone_heart.id] = 1
	breakthrough.dialogue_choices[&"foundation_choice"] = &"flowing_water"
	await story.run(LanternPassStory.ATTEMPT_BREAKTHROUGH, breakthrough)
	_expect(
		breakthrough.source_completed
		and breakthrough.stage == &"foundation_established"
		and breakthrough.recorded_foundation_id == story.flowing_water_foundation.id
		and breakthrough.recorded_catalyst_id == story.stone_heart.id
		and breakthrough.played_sound_paths.has(story.breakthrough_sound.resource_path)
		and breakthrough.inventory_quantities.get(story.stone_heart.id, 0) == 0,
		"a valid foundation choice should consume the catalyst and atomically establish the foundation"
	)
	var final_test := FakeStoryContext.new()
	final_test.stage = &"foundation_established"
	final_test.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await story.run(LanternPassStory.FINAL_TEST, final_test)
	_expect(
		final_test.source_completed and final_test.stage == &"mvp_complete",
		"the post-breakthrough pack should finish the MVP exactly once"
	)


func _test_battle_trigger_event() -> void:
	var encounter := _test_encounter()
	var event := BattleTriggerEvent.new()
	event.encounter = encounter
	var victory := FakeStoryContext.new()
	victory.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await event.run(&"default", victory)
	_expect(victory.source_completed, "Victory should complete a BattleTriggerEvent source")
	var escaped := FakeStoryContext.new()
	escaped.next_battle_result.outcome = BattleResult.Outcome.ESCAPED
	await event.run(&"default", escaped)
	_expect(
		not escaped.source_completed and not escaped.party_restored,
		"Escaped should preserve the source without restoring the party"
	)
	var defeat_map := MapDefinition.new()
	defeat_map.id = &"map.test.safe"
	defeat_map.default_spawn_id = &"safe"
	event.defeat_map = defeat_map
	event.defeat_spawn_id = &"safe"
	var defeated := FakeStoryContext.new()
	defeated.next_battle_result.outcome = BattleResult.Outcome.DEFEAT
	await event.run(&"default", defeated)
	_expect(
		defeated.party_restored
		and defeated.recorded_pending_map == defeat_map
		and defeated.recorded_pending_spawn_id == &"safe",
		"Defeat should restore the party and register terminal travel"
	)


func _test_random_state() -> void:
	var first := RandomState.new()
	first.initialize(117)
	first.roll_percent(50)
	var restored := RandomState.new()
	_expect(restored.restore(first.to_dictionary()), "random source should restore from save data")
	_expect(
		first.roll_percent(50) == restored.roll_percent(50),
		"restored random source should continue the same deterministic sequence"
	)


func _test_cultivation_rules() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	_expect(database.build_index().is_empty(), "cultivation test database should validate")
	var run := GameRun.new_game(database, 771)
	var leader := run.party.leader()
	var actor := database.actor(leader.definition_id)
	_expect(
		leader.realm_id == &"realm.qi_refining"
		and leader.realm_layer == 7
		and leader.cultivation_points == 0,
		"new MVP game should start at qi refining layer seven"
	)
	_expect(
		leader.hp == CultivationRules.max_hp(actor, leader, database)
		and leader.mp == CultivationRules.max_mp(actor, leader, database),
		"new actors should start with cultivation-derived full HP and MP"
	)
	var cadence := GameRun.new_game(database, 770).party.leader()
	var cadence_encounters: Array[StringName] = [
		&"encounter.roadside.lantern_pass.first_pack",
		&"encounter.roadside.lantern_pass.second_pack",
		&"encounter.roadside.lantern_pass.third_pack",
		&"encounter.roadside.lantern_pass.elite",
		&"encounter.roadside.lantern_pass_beast",
	]
	var expected_layers := PackedInt32Array([7, 8, 9, 9, 9])
	var expected_points := PackedInt32Array([32, 40, 50, 90, 100])
	for encounter_index: int in range(cadence_encounters.size()):
		var encounter := database.encounter(cadence_encounters[encounter_index])
		var reward := 0
		for entry: EncounterEnemy in encounter.enemies:
			reward += entry.enemy.cultivation_reward
		CultivationRules.gain_cultivation(cadence, reward, database)
		_expect(
			cadence.realm_layer == expected_layers[encounter_index]
			and cadence.cultivation_points == expected_points[encounter_index],
			"lantern encounter %s should produce the authored cultivation cadence"
			% cadence_encounters[encounter_index]
		)
	_expect(
		CultivationRules.is_ready_for_breakthrough(cadence, database),
		"the five pre-foundation lantern victories should exactly reach breakthrough readiness"
	)
	var first_gain := CultivationRules.gain_cultivation(leader, 60, database)
	_expect(
		first_gain.succeeded()
		and first_gain.layers_gained == 1
		and leader.realm_layer == 8
		and leader.cultivation_points == 0,
		"cultivation should consume the configured layer cost"
	)
	CultivationRules.gain_cultivation(leader, 170, database)
	_expect(
		leader.realm_layer == 9
		and leader.cultivation_points == 100
		and CultivationRules.is_ready_for_breakthrough(leader, database),
		"max-layer cultivation should cap at the breakthrough requirement"
	)
	var foundation := database.foundation(&"foundation.sharp_metal")
	var breakthrough := CultivationRules.breakthrough(leader, foundation, database)
	_expect(
		breakthrough.succeeded()
		and leader.realm_id == &"realm.foundation_establishment"
		and leader.realm_layer == 1
		and leader.foundation_id == foundation.id
		and leader.cultivation_points == 0,
		"a valid foundation should atomically advance the actor into foundation establishment"
	)
	var legacy := GameRun.new_game(database, 772).to_dictionary()
	legacy["save_version"] = GameRun.THREE_DIMENSIONAL_SAVE_VERSION
	var legacy_actor: Dictionary = legacy["party"]["members"][0]
	legacy_actor.erase("realm_id")
	legacy_actor.erase("realm_layer")
	legacy_actor.erase("cultivation_points")
	legacy_actor.erase("foundation_id")
	legacy_actor["level"] = 8
	legacy_actor["experience"] = 5
	var migrated := GameRun.from_dictionary(legacy, database)
	_expect(
		migrated != null
		and migrated.party.leader().realm_id == &"realm.qi_refining"
		and migrated.party.leader().realm_layer == 8
		and migrated.party.leader().cultivation_points == 5,
		"version four level and experience should migrate into cultivation state"
	)
	var catalyst_run := GameRun.new_game(database, 773)
	var catalyst_actor := catalyst_run.party.leader()
	CultivationRules.gain_cultivation(catalyst_actor, 230, database)
	var catalyst := database.item(&"item.roadside.qi_eating_stone_heart")
	var missing := CultivationTransaction.breakthrough(
		catalyst_run,
		database.foundation(&"foundation.flowing_water"),
		catalyst,
		database
	)
	_expect(
		missing.outcome == CultivationResult.Outcome.CATALYST_REQUIRED
		and catalyst_actor.realm_id == &"realm.qi_refining",
		"breakthrough transaction should leave cultivation unchanged without its catalyst"
	)
	catalyst_run.inventory.add_item(catalyst, 1)
	var completed := CultivationTransaction.breakthrough(
		catalyst_run,
		database.foundation(&"foundation.flowing_water"),
		catalyst,
		database
	)
	_expect(
		completed.succeeded()
		and catalyst_run.inventory.quantity(catalyst.id) == 0
		and &"skill.roadside.origin_sword_array" in catalyst_actor.learned_skill_ids
		and catalyst_actor.battle_skill_ids[2] == &"skill.roadside.origin_sword_array"
		and catalyst_actor.hp == CultivationRules.max_hp(
			actor,
			catalyst_actor,
			database
		),
		"breakthrough transaction should consume one catalyst, grant the ultimate, and refill derived stats"
	)


func _test_equipment_transaction() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	_expect(database.build_index().is_empty(), "equipment transaction database should validate")
	var run := GameRun.new_game(database, 881)
	run.location.map_id = &"map.roadside.north_slope_wilds"
	var leader := run.party.leader()
	var sword_case := database.item(&"item.roadside.returning_sword_case") as EquipmentDefinition
	var sword_seal := database.item(&"item.roadside.suppressing_sword_seal") as EquipmentDefinition
	run.inventory.add_item(sword_case, 1)
	run.inventory.add_item(sword_seal, 1)
	var first := EquipmentTransaction.equip(run, leader, sword_case, database)
	_expect(
		first.succeeded()
		and leader.equipment.get(&"weapon") == sword_case.id
		and run.inventory.quantity(sword_case.id) == 0,
		"equipping a carried weapon should remove it from inventory and update ActorState"
	)
	var replacement := EquipmentTransaction.equip(run, leader, sword_seal, database)
	_expect(
		replacement.succeeded()
		and replacement.returned_item_id == sword_case.id
		and leader.equipment.get(&"weapon") == sword_seal.id
		and run.inventory.quantity(sword_case.id) == 1
		and run.inventory.quantity(sword_seal.id) == 0,
		"replacing a weapon should atomically return the previous equipment"
	)
	var unequipped := EquipmentTransaction.unequip(run, leader, &"weapon", database)
	_expect(
		unequipped.outcome == EquipmentResult.Outcome.UNEQUIPPED
		and not leader.equipment.has(&"weapon")
		and run.inventory.quantity(sword_seal.id) == 1,
		"unequipping should atomically return the current weapon to inventory"
	)
	_expect(
		database.validate_game_run(run).is_empty(),
		"equipped MVP build state should remain valid save content"
	)


func _test_inventory_and_loadout_transactions() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	_expect(database.build_index().is_empty(), "inventory/loadout database should validate")
	var run := GameRun.new_game(database, 884)
	run.location.map_id = &"map.roadside.lantern_pass"
	var leader := run.party.leader()
	var herb := database.item(&"item.roadside.fanqing_grass")
	var catalyst := database.item(&"item.roadside.qi_eating_stone_heart")
	var medicine := database.item(&"item.roadside.wound_powder")
	run.inventory.max_distinct_items = 1
	_expect(run.inventory.add_item(herb, 1).succeeded(), "the first regular item should use capacity")
	_expect(
		run.inventory.add_item(catalyst, 1).succeeded()
		and run.inventory.occupied_capacity() == 1,
		"key items should not consume regular inventory capacity"
	)
	_expect(
		not run.inventory.add_item(medicine, 1).succeeded()
		and run.inventory.quantity(medicine.id) == 0,
		"a second regular item type should be rejected at capacity"
	)
	_expect(
		ItemDiscardTransaction.discard(run, catalyst, 1).outcome
		== ItemDiscardResult.Outcome.NOT_DISCARDABLE,
		"key items should not be discardable"
	)
	_expect(
		ItemDiscardTransaction.discard(run, herb, 1).succeeded()
		and run.inventory.add_item(medicine, 2).succeeded(),
		"discarding a regular item should free capacity atomically"
	)
	var quick := BattleItemLoadoutTransaction.assign(run, leader, medicine, database)
	_expect(
		quick.outcome == BattleItemLoadoutResult.Outcome.ASSIGNED
		and leader.battle_item_id == medicine.id,
		"a carried battle consumable should be assignable to the action bar"
	)
	var wind := database.skill(&"skill.roadside.wind_edge")
	var ultimate := database.skill(&"skill.roadside.origin_sword_array")
	var unlearned := SkillLoadoutTransaction.assign(leader, ultimate, 2, database)
	_expect(
		unlearned.outcome == SkillLoadoutResult.Outcome.SKILL_NOT_LEARNED,
		"unlearned skills should not enter battle slots"
	)
	var moved := SkillLoadoutTransaction.assign(leader, wind, 2, database)
	_expect(
		moved.succeeded()
		and leader.battle_skill_ids[0].is_empty()
		and leader.battle_skill_ids[2] == wind.id,
		"assigning an equipped skill elsewhere should move it without duplication"
	)
	var learned := SkillLearningTransaction.learn(leader, ultimate, database)
	_expect(
		learned.succeeded()
		and learned.auto_equipped
		and learned.slot_index == 0
		and leader.learned_skill_ids.has(ultimate.id)
		and leader.battle_skill_ids[0] == ultimate.id,
		"learning a skill should fill the first empty battle slot"
	)
	_expect(
		database.validate_game_run(run).is_empty(),
		"inventory and loadout transactions should leave a valid GameRun"
	)


func _test_item_delivery() -> void:
	var item := load("res://content/items/fanqing_grass.tres") as ItemDefinition
	var run := GameRun.new()
	run.economy.money = 18
	var missing := ItemDeliveryTransaction.exchange(run, item, 2, 12)
	_expect(
		missing.outcome == DeliveryResult.Outcome.INSUFFICIENT_ITEMS
		and run.economy.money == 18,
		"failed delivery should not change money"
	)
	run.inventory.add_item(item, 2)
	var completed := ItemDeliveryTransaction.exchange(run, item, 2, 12)
	_expect(
		completed.completed()
		and run.inventory.quantity(item.id) == 0
		and run.economy.money == 30,
		"delivery should remove exact items and add wages atomically"
	)


func _test_game_run_round_trip() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	database.build_index()
	var run := GameRun.new_game(database)
	run.location.map_id = &"map.roadside.shop"
	run.location.spawn_id = &"default"
	run.location.position = Vector3(48, 3, 192)
	run.location.direction = &"east"
	run.location.has_exact_position = true
	run.randomness.initialize(9182)
	run.randomness.roll_percent(50)
	var medicine := database.item(&"item.roadside.wound_powder")
	run.inventory.add_item(medicine, 1)
	run.party.leader().battle_item_id = medicine.id
	var restored := GameRun.from_dictionary(run.to_dictionary(), database)
	_expect(restored != null, "GameRun should round-trip the new content version")
	if restored == null:
		return
	_expect(
		restored.party.leader_id == &"actor.roadside.traveler",
		"GameRun should preserve the original traveler"
	)
	_expect(restored.location.map_id == &"map.roadside.shop", "location should round-trip")
	_expect(restored.location.position == Vector3(48, 3, 192), "exact 3D position should round-trip")
	_expect(
		restored.party.leader().battle_skill_ids == run.party.leader().battle_skill_ids
		and restored.party.leader().battle_item_id == medicine.id,
		"v6 should round-trip learned skills, battle slots, and the battle item"
	)
	var previous_data := run.to_dictionary()
	previous_data["save_version"] = GameRun.PREVIOUS_SAVE_VERSION
	var previous_actor: Dictionary = previous_data["party"]["members"][0]
	previous_actor["skill_ids"] = previous_actor["learned_skill_ids"]
	previous_actor.erase("learned_skill_ids")
	previous_actor.erase("battle_skill_ids")
	previous_actor.erase("battle_item_id")
	var previous_migrated := GameRun.from_dictionary(previous_data, database)
	_expect(
		previous_migrated != null
		and previous_migrated.party.leader().learned_skill_ids.size() == 2
		and previous_migrated.party.leader().battle_skill_ids[0] == &"skill.roadside.wind_edge"
		and previous_migrated.party.leader().battle_item_id == medicine.id,
		"v5 should migrate skill_ids and the first usable inventory item into v6 loadout state"
	)
	var legacy_data := run.to_dictionary()
	legacy_data["save_version"] = GameRun.TWO_DIMENSIONAL_SAVE_VERSION
	legacy_data["location"]["position"] = [24.0, 96.0]
	legacy_data["location"]["spawn_id"] = ""
	var migrated := GameRun.from_dictionary(legacy_data)
	_expect(
		migrated != null
		and migrated.location.position == Vector3.ZERO
		and not migrated.location.has_exact_position
		and migrated.location.migrated_from_2d_position,
		"version 3 exact 2D positions should fall back to a semantic spawn"
	)
	_expect(
		restored.randomness.draw_count == 1
		and restored.randomness.roll_percent(50) == run.randomness.roll_percent(50),
		"seeded random progress should round-trip"
	)


func _test_save_service() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	database.build_index()
	var service := SaveService.new()
	service.configure(database)
	service.configure_slots_directory(TEST_SLOTS)
	var run := GameRun.new_game(database)
	run.location.map_id = &"map.roadside.shop"
	_expect(service.save_run(run, TEST_SAVE) == OK, "SaveService should save original content")
	var restored := service.load_run(TEST_SAVE)
	_expect(
		restored != null and restored.location.map_id == &"map.roadside.shop",
		"SaveService should restore the roadside map"
	)
	run.economy.money = 77
	run.flags.set_value(&"flag.test.legacy", true)
	run.world.complete(&"map.roadside.shop", &"entity.test.completed")
	var legacy_data := run.to_dictionary()
	legacy_data["save_version"] = GameRun.TWO_DIMENSIONAL_SAVE_VERSION
	legacy_data["location"] = {
		"map_id": "map.roadside.shop",
		"spawn_id": "",
		"position": [240.0, 120.0],
		"direction": "east",
		"has_exact_position": true,
	}
	var legacy_file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	_expect(legacy_file != null, "save migration test should write a version 3 fixture")
	if legacy_file != null:
		legacy_file.store_string(JSON.stringify(legacy_data))
		legacy_file.close()
	var migrated := service.load_run(TEST_SAVE)
	_expect(
		migrated != null
		and not migrated.location.has_exact_position
		and migrated.location.spawn_id == &"default"
		and migrated.economy.money == 77
		and migrated.flags.is_set(&"flag.test.legacy")
		and migrated.world.is_completed(
			&"map.roadside.shop", &"entity.test.completed"
		),
		"version 3 saves should preserve progress while falling back to a semantic spawn"
	)
	_expect(service.save_slot(run, 1) == OK, "formal slot should save")
	var summary := service.slot_summary(1)
	_expect(
		summary.get("map_name") == "斜坡小铺" and summary.get("leader_name") == "旅人",
		"slot summary should use new original display names"
	)
	_remove_if_exists(TEST_SAVE)
	_remove_if_exists(service.slot_path(1))
	_remove_directory_if_empty(TEST_SLOTS)
	service.free()


func _test_save_baseline_fixtures() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	database.build_index()
	for path: String in [
		"res://tests/fixtures/save_baselines/new_game_v3.json",
		"res://tests/fixtures/save_baselines/gathering_completed_v3.json",
		"res://tests/fixtures/save_baselines/new_game_v6.json",
		"res://tests/fixtures/save_baselines/lantern_foundation_v6.json",
	]:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var run := (
			GameRun.from_dictionary(parsed, database)
			if parsed is Dictionary
			else null
		)
		_expect(
			run != null and database.validate_game_run(run).is_empty(),
			"save baseline should load and validate: %s" % path
		)
	var configured_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/save_baselines/lantern_foundation_v6.json"
	))
	var configured := GameRun.from_dictionary(configured_data, database)
	_expect(
		configured != null
		and configured.party.leader().foundation_id == &"foundation.sharp_metal"
		and configured.party.leader().battle_skill_ids[2]
		== &"skill.roadside.origin_sword_array"
		and configured.party.leader().battle_item_id == &"item.roadside.wound_powder",
		"the v6 configured baseline should preserve foundation equipment and loadout state"
	)


func _test_settings_service() -> void:
	var root := Node.new()
	get_root().add_child(root)
	var audio := AudioService.new()
	var music_player := AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	audio.add_child(music_player)
	var sound_player := AudioStreamPlayer.new()
	sound_player.name = "SoundPlayer"
	audio.add_child(sound_player)
	root.add_child(audio)
	var service := SettingsService.new()
	root.add_child(service)
	audio.configure()
	service.configure(audio, TEST_SETTINGS)
	service.set_locale(&"en")
	service.set_key_binding(&"interact", KEY_E)
	service.set_key_binding(&"combat_skill_three", KEY_G)
	var mouse_binding := InputEventMouseButton.new()
	mouse_binding.button_index = MOUSE_BUTTON_MIDDLE
	service.set_input_binding(
		&"combat_skill_one", SettingsService.BindingSlot.MOUSE, mouse_binding
	)
	var gamepad_binding := InputEventJoypadButton.new()
	gamepad_binding.button_index = JOY_BUTTON_LEFT_STICK
	service.set_input_binding(
		&"combat_target_next", SettingsService.BindingSlot.GAMEPAD, gamepad_binding
	)
	service.set_input_tuning(0.22, 0.31, 1.35)
	service.set_accessibility(72.0, true)
	service.set_display_mode(SettingsService.DISPLAY_MODE_WINDOW_3X)
	service.set_display_mode(SettingsService.DISPLAY_MODE_FULLSCREEN)
	_expect(service.locale == &"en", "settings should persist locale choice")
	_expect(service.key_for_action(&"interact") == KEY_E, "settings should rebind interact")
	_expect(
		service.key_for_action(&"combat_skill_three") == KEY_G,
		"settings should rebind combat actions shown by the HUD"
	)
	_expect(
		service.binding_label(&"combat_skill_one", SettingsService.BindingSlot.MOUSE) == "鼠中"
		and service.binding_label(
			&"combat_target_next", SettingsService.BindingSlot.GAMEPAD
		) == "L3",
		"settings should support independent mouse and gamepad bindings"
	)
	var config := ConfigFile.new()
	_expect(config.load(TEST_SETTINGS) == OK, "settings should save display preferences")
	_expect(
		config.get_value("display", "window_mode") == "fullscreen"
		and config.get_value("display", "windowed_mode") == "window_3x",
		"settings should preserve fullscreen and the last exact window scale"
	)
	_expect(
		int(config.get_value("input", "version", 0))
		== SettingsService.INPUT_BINDINGS_VERSION,
		"settings should persist the current input binding version"
	)
	_expect(
		is_equal_approx(float(config.get_value("input", "movement_deadzone")), 0.22)
		and is_equal_approx(float(config.get_value("input", "aim_deadzone")), 0.31)
		and is_equal_approx(float(config.get_value("input", "aim_sensitivity")), 1.35)
		and config.get_value("input_mouse", "combat_skill_one") == "mouse:3"
		and config.get_value("input_gamepad", "combat_target_next")
		== "button:%d" % int(JOY_BUTTON_LEFT_STICK),
		"settings should persist stick tuning and device-specific bindings"
	)
	_expect(
		is_equal_approx(
			float(config.get_value("accessibility", "dialogue_text_speed")), 72.0
		)
		and bool(config.get_value("accessibility", "reduce_combat_flashes")),
		"settings should persist dialogue pacing and reduced combat flashes"
	)
	service.load_settings()
	_expect(
		is_equal_approx(service.movement_deadzone, 0.22)
		and is_equal_approx(service.aim_deadzone, 0.31)
		and is_equal_approx(service.aim_sensitivity, 1.35)
		and is_equal_approx(service.dialogue_text_speed, 72.0)
		and service.reduce_combat_flashes,
		"settings should restore clamped input tuning and accessibility preferences"
	)
	service.toggle_fullscreen(false)
	_expect(
		service.display_mode == SettingsService.DISPLAY_MODE_WINDOW_3X,
		"leaving fullscreen should restore the last windowed scale"
	)
	service.set_display_mode(&"unsupported", false)
	_expect(
		service.display_mode == SettingsService.DISPLAY_MODE_WINDOW_2X,
		"unknown display modes should fall back to the default 2x window"
	)
	service.set_display_mode(SettingsService.DISPLAY_MODE_WINDOW_3X, false)
	var settings_scene := (
		load("res://game/presentation/settings/settings_game_scene.tscn") as PackedScene
	).instantiate() as SettingsGameScene
	root.add_child(settings_scene)
	var context := GameSceneContext.new()
	context.settings_service = service
	settings_scene.enter(context, null)
	var display_option := settings_scene.get_node(^"UiLayer/Panel/Display") as OptionButton
	var binding_device_option := settings_scene.get_node(
		^"UiLayer/Panel/BindingDevice"
	) as OptionButton
	var action_list := settings_scene.get_node(^"UiLayer/Panel/Actions") as ItemList
	var dialogue_speed := settings_scene.get_node(
		^"UiLayer/Panel/DialogueSpeed"
	) as OptionButton
	var reduce_flashes := settings_scene.get_node(
		^"UiLayer/Panel/ReduceCombatFlashes"
	) as CheckButton
	_expect(
		display_option.item_count == SettingsService.SUPPORTED_DISPLAY_MODES.size()
		and display_option.selected == 1,
		"settings UI should expose 2x, 3x, and fullscreen and select the saved mode"
	)
	_expect(
		binding_device_option.item_count == 3
		and action_list.item_count == SettingsService.REBINDABLE_ACTIONS.size(),
		"settings UI should expose keyboard, mouse, and gamepad bindings for every action"
	)
	_expect(
		dialogue_speed.item_count == SettingsGameScene.DIALOGUE_SPEEDS.size()
		and dialogue_speed.selected == 2
		and reduce_flashes.button_pressed,
		"settings UI should expose saved dialogue speed and reduced-flash controls"
	)
	var category_game := settings_scene.get_node(
		^"UiLayer/Panel/CategoryGame"
	) as Button
	var keyboard_tab := settings_scene.get_node(^"UiLayer/Panel/KeyboardTab") as Button
	_expect(
		category_game.button_pressed
		and (settings_scene.get_node(^"UiLayer/Panel/Language") as Control).visible
		and not action_list.visible,
		"settings should open on one focused category instead of a flat tool panel"
	)
	settings_scene._show_category(SettingsGameScene.SettingsCategory.CONTROLS)
	_expect(
		keyboard_tab.visible
		and keyboard_tab.button_pressed
		and action_list.visible
		and not (settings_scene.get_node(^"UiLayer/Panel/Language") as Control).visible,
		"controls should expose device tabs and the action list on their own page"
	)
	var conflicting_key := InputEventKey.new()
	conflicting_key.physical_keycode = KEY_E
	_expect(
		service.conflicting_action(
			&"combat_item",
			SettingsService.BindingSlot.KEYBOARD,
			conflicting_key
		) == &"interact",
		"rebinding should identify an existing same-device binding conflict"
	)
	var secondary_menu_key := InputEventKey.new()
	secondary_menu_key.physical_keycode = KEY_M
	_expect(
		service.conflicting_action(
			&"combat_item",
			SettingsService.BindingSlot.KEYBOARD,
			secondary_menu_key
		) == &"menu",
		"conflict checks should include the required secondary menu shortcut"
	)
	var feedback := CombatFeedback3D.new()
	root.add_child(feedback)
	feedback.configure(service)
	var flash_actor := Node3D.new()
	var flash_mesh := MeshInstance3D.new()
	flash_mesh.mesh = BoxMesh.new()
	flash_actor.add_child(flash_mesh)
	root.add_child(flash_actor)
	feedback.flash_actor(flash_actor)
	_expect(
		flash_mesh.material_overlay == null
		and (feedback.get("_flash_tweens") as Dictionary).is_empty(),
		"reduced-flash mode should skip actor overlay flashes"
	)
	feedback.queue_free()
	flash_actor.queue_free()
	for event: InputEvent in InputMap.action_get_events(&"combat_skill_one"):
		if event is InputEventKey:
			InputMap.action_erase_event(&"combat_skill_one", event)
	service.set_key_binding(&"combat_skill_two", KEY_1, false)
	service.set_key_binding(&"combat_skill_three", KEY_2, false)
	service.set_key_binding(&"combat_item", KEY_Q, false)
	var legacy_config := ConfigFile.new()
	legacy_config.set_value("input", "combat_skill_one", int(KEY_Q))
	legacy_config.set_value("input", "combat_skill_two", int(KEY_E))
	legacy_config.set_value("input", "combat_skill_three", int(KEY_F))
	legacy_config.set_value("input", "combat_item", int(KEY_R))
	_expect(
		legacy_config.save(TEST_SETTINGS) == OK,
		"settings test should write a legacy input fixture"
	)
	service.load_settings()
	_expect(
		service.key_for_action(&"combat_skill_one") == KEY_NONE
		and service.key_for_action(&"combat_skill_two") == KEY_1
		and service.key_for_action(&"combat_skill_three") == KEY_2
		and service.key_for_action(&"combat_item") == KEY_Q,
		"legacy Q/E/F/R bindings should migrate to the ARPG defaults"
	)
	service.reset_input_bindings(false)
	var escape_key := InputEventKey.new()
	escape_key.physical_keycode = KEY_ESCAPE
	var menu_key := InputEventKey.new()
	menu_key.physical_keycode = KEY_M
	_expect(
		InputMap.action_has_event(&"menu", escape_key)
		and InputMap.action_has_event(&"menu", menu_key),
		"menu defaults should keep Esc primary and M as a secondary keyboard shortcut"
	)
	service.set_locale(&"zh_CN", false)
	_remove_if_exists(TEST_SETTINGS)
	root.queue_free()


func _test_r9_field_test_input_logger() -> void:
	_remove_if_exists(TEST_R9_INPUT_LOG)
	var logger := R9FieldTestInputLogger.new()
	get_root().add_child(logger)
	_expect(
		logger.start(TEST_R9_INPUT_LOG) == OK,
		"R9 field-test logger should create a fresh JSONL evidence file"
	)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	logger._input(key)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(320.0, 180.0)
	mouse.pressed = true
	logger._input(mouse)
	logger.stop()
	var duplicate := R9FieldTestInputLogger.new()
	get_root().add_child(duplicate)
	_expect(
		duplicate.start(TEST_R9_INPUT_LOG) == ERR_ALREADY_EXISTS,
		"R9 field-test logger should not overwrite an existing evidence log"
	)
	duplicate.queue_free()
	logger.queue_free()
	var file := FileAccess.open(TEST_R9_INPUT_LOG, FileAccess.READ)
	var records: Array[Dictionary] = []
	if file != null:
		while not file.eof_reached():
			var line := file.get_line().strip_edges()
			if line.is_empty():
				continue
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary:
				records.append(parsed as Dictionary)
		file.close()
	_expect(
		records.size() == 4
		and records[0].get("kind") == "session_start"
		and records[1].get("type") == "key"
		and (records[1].get("actions", []) as Array).has("move_north")
		and records[2].get("type") == "mouse_button"
		and records[3].get("kind") == "session_end",
		"R9 field-test logger should preserve session metadata and chronological real input"
	)
	_remove_if_exists(TEST_R9_INPUT_LOG)


func _test_r9_field_test_validator() -> void:
	var template_file := FileAccess.open(
		"res://docs/baselines/r9/field-test-results.template.json",
		FileAccess.READ
	)
	_expect(template_file != null, "R9 field-test results template should be readable")
	if template_file == null:
		return
	var parsed: Variant = JSON.parse_string(template_file.get_as_text())
	template_file.close()
	_expect(parsed is Dictionary, "R9 field-test results template should contain valid JSON")
	if not parsed is Dictionary:
		return
	var validator := R9FieldTestValidator.new()
	var pending := validator.validate(parsed as Dictionary, false)
	_expect(
		not bool(pending.get("ok", true))
		and int((pending.get("recordings", {}) as Dictionary).get("found", 0)) == 4,
		"R9 field-test validator should reject an untouched pending template"
	)
	var complete := (parsed as Dictionary).duplicate(true)
	complete["date"] = "2026-08-20"
	complete["build_commit"] = "1234567890abcdef"
	complete["godot_revision"] = "4173760fdf6c2c722e82e08cb58e55f34c9efd80"
	for raw_recording: Variant in complete.get("recordings", []):
		var recording := raw_recording as Dictionary
		recording["duration_seconds"] = 90.0
		recording["reviewed"] = true
		recording["result"] = "pass"
		var checks := recording.get("checks", {}) as Dictionary
		for check_id: Variant in checks.keys():
			checks[check_id] = true
	for raw_participant: Variant in complete.get("participants", []):
		var participant := raw_participant as Dictionary
		participant["device_model"] = "test device"
		participant["first_move_seconds"] = 10.0
		participant["interaction_understood_seconds"] = 45.0
		participant["basic_attack"] = true
		participant["skill"] = true
		participant["dodge"] = true
		participant["distinguished_hp_mp"] = true
		participant["menu_settings_roundtrip"] = true
		participant["quotes"] = ["raw observation"]
	var passed := validator.validate(complete, false)
	_expect(
		bool(passed.get("ok", false))
		and int((passed.get("recordings", {}) as Dictionary).get("passed", 0)) == 4
		and int((passed.get("participants", {}) as Dictionary).get("combat_passed", 0)) == 5,
		"R9 field-test validator should accept all four reviewed recordings and five passing participants"
	)
	var failed := complete.duplicate(true)
	((failed.get("participants", []) as Array)[0] as Dictionary)["severe_failures"] = [
		"input lock"
	]
	_expect(
		not bool(validator.validate(failed, false).get("ok", true)),
		"R9 field-test validator should reject any severe first-player failure"
	)


func _test_scene_stack() -> void:
	var stack := GameSceneStack.new()
	get_root().add_child(stack)
	stack.configure(func() -> GameSceneContext: return GameSceneContext.new())
	var fixture := _pack_scene_stack_fixture()
	_expect(stack.reset(fixture, {"name": "root"}), "scene stack should reset")
	var root_scene := stack.current_scene() as SceneStackTestScene
	_capture_scene_stack_result(stack, fixture)
	await process_frame
	_expect(stack.scene_count() == 2, "scene stack should push a modal scene")
	_expect(root_scene.pause_count == 1, "push should pause the map")
	stack.pop({"closed": true})
	await process_frame
	_expect(_scene_stack_result_received, "pop should resume the awaiting caller")
	_expect(_scene_stack_result == {"closed": true}, "pop should return its result")
	_expect(root_scene.resume_count == 1, "pop should resume the map")
	stack.queue_free()
	await process_frame


func _test_game_root_smoke() -> void:
	var packed := load("res://game/bootstrap/game_root.tscn") as PackedScene
	var game_root := packed.instantiate() as GameRoot
	get_root().add_child(game_root)
	await process_frame
	_expect(
		game_root.asset_library.diagnostics.is_empty(),
		"GameRoot should initialize only original assets"
	)
	game_root.start_new_game()
	await process_frame
	await process_frame
	var map_scene := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		map_scene != null
		and map_scene.map_id == &"map.roadside.lantern_pass"
		and game_root.game_run.location.map_id == map_scene.map_id,
		"new game should enter the lantern-pass cultivation MVP"
	)
	_expect(
		map_scene != null
		and map_scene.story_module is LanternPassStory
		and map_scene.get_node(^"WorldRoot/EncounterSources").get_child_count() == 6
		and map_scene.get_node_or_null(^"WorldRoot/LanternKeeper") is NpcCharacter3D,
		"new game should expose the R7 story, six encounters, and lantern keeper"
	)
	_expect(InputMap.has_action(&"toggle_fullscreen"), "F11 fullscreen action should be registered")
	_expect(
		game_root.settings_service.binding_label(
			&"combat_skill_one", SettingsService.BindingSlot.MOUSE
		) == "鼠右"
		and game_root.settings_service.key_for_action(&"combat_skill_two") == KEY_1
		and game_root.settings_service.key_for_action(&"combat_skill_three") == KEY_2
		and game_root.settings_service.key_for_action(&"combat_item") == KEY_Q,
		"GameRoot should install right-click, 1, 2, and Q as the ARPG combat defaults"
	)
	var escape_menu := InputEventKey.new()
	escape_menu.physical_keycode = KEY_ESCAPE
	var start_menu := InputEventJoypadButton.new()
	start_menu.button_index = JOY_BUTTON_START
	_expect(
		InputMap.action_has_event(&"menu", escape_menu)
		and InputMap.action_has_event(&"menu", start_menu),
		"map menu should have Esc and gamepad Start parity"
	)
	var menu_medicine := game_root.content_database.item(&"item.roadside.wound_powder")
	var menu_equipment := game_root.content_database.item(
		&"item.roadside.returning_sword_case"
	)
	game_root.game_run.inventory.add_item(menu_medicine, 2)
	game_root.game_run.inventory.add_item(menu_equipment, 1)
	var open_menu := InputEventAction.new()
	open_menu.action = &"menu"
	open_menu.pressed = true
	game_root._unhandled_input(open_menu)
	await process_frame
	_expect(
		game_root.scene_stack.current_scene() is MenuGameScene,
		"the menu action should pause the active map and open the menu scene"
	)
	var menu_scene := game_root.scene_stack.current_scene() as MenuGameScene
	_expect(
		menu_scene != null
		and menu_scene.inventory_empty.visible == (menu_scene.inventory_items.item_count == 0)
		and not menu_scene.status_summary.text.is_empty()
		and menu_scene.get_node(^"UiLayer/Panel/Tabs/Status").has_focus(),
		"pause menu should expose status, inventory empty state, and a visible focus target"
	)
	menu_scene._show_page(MenuGameScene.Page.INVENTORY, true)
	_expect(
		menu_scene.inventory_items.item_count == 2
		and menu_scene.inventory_items.has_focus(),
		"inventory page should list carried items and own focus"
	)
	menu_scene.inventory_items.select(0)
	menu_scene._select_inventory_item(0)
	menu_scene._assign_selected_quick_item()
	_expect(
		game_root.game_run.party.leader().battle_item_id == menu_medicine.id,
		"inventory page should configure the selected battle item through its transaction"
	)
	menu_scene._show_page(MenuGameScene.Page.EQUIPMENT, true)
	_expect(
		menu_scene.equipment_candidates.item_count == 1,
		"equipment page should list compatible carried artifacts"
	)
	menu_scene.equipment_candidates.select(0)
	menu_scene._select_equipment_candidate(0)
	menu_scene._equip_selected_candidate()
	_expect(
		game_root.game_run.party.leader().equipment.get(&"weapon") == menu_equipment.id,
		"equipment page should equip the selected artifact atomically"
	)
	menu_scene._show_page(MenuGameScene.Page.SKILLS, true)
	menu_scene.learned_skills.select(0)
	menu_scene._select_learned_skill(0)
	menu_scene._assign_selected_skill(2)
	_expect(
		game_root.game_run.party.leader().battle_skill_ids[2]
		== &"skill.roadside.wind_edge",
		"skills page should move a learned skill into the selected battle slot"
	)
	menu_scene._assign_selected_skill(0)
	menu_scene._show_page(MenuGameScene.Page.SYSTEM, true)
	menu_scene.settings_button.grab_focus()
	menu_scene._open_settings()
	await process_frame
	_expect(
		game_root.scene_stack.current_scene() is SettingsGameScene,
		"system page should push the settings scene"
	)
	game_root.scene_stack.pop()
	await process_frame
	menu_scene = game_root.scene_stack.current_scene() as MenuGameScene
	_expect(
		menu_scene != null
		and menu_scene._current_page == MenuGameScene.Page.SYSTEM
		and menu_scene.settings_button.has_focus(),
		"returning from a child scene should preserve the menu page and focus"
	)
	var close_menu := InputEventAction.new()
	close_menu.action = &"ui_cancel"
	close_menu.pressed = true
	menu_scene._unhandled_input(close_menu)
	await process_frame
	map_scene = game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		map_scene != null,
		"Esc/B should return from the menu to the same map"
	)
	if map_scene != null:
		map_scene.set_process(false)
		var encounter := _test_encounter()
		var result_holder: Dictionary = {}
		map_scene.battle_finished.connect(func(result: BattleResult) -> void:
			result_holder["result"] = result
		)
		var session := map_scene.begin_battle(encounter)
		_expect(
			session != null
			and map_scene.has_active_battle()
			and game_root.scene_stack.scene_count() == 1,
			"map-local combat should own one BattleSession without pushing GameSceneStack"
		)
		_expect(
			map_scene.player_3d.control_enabled and not map_scene.player_3d.interaction_enabled,
			"active combat should allow movement while suppressing interaction"
		)
		game_root._unhandled_input(open_menu)
		_expect(
			game_root.scene_stack.current_scene() == map_scene
			and game_root.scene_stack.scene_count() == 1,
			"active combat should reject equipment and loadout menu entry"
		)
		var blocked_save := game_root.save_service.save_run(game_root.game_run, TEST_SAVE)
		_expect(
			blocked_save == ERR_BUSY
			and game_root.save_service.last_diagnostic.get("code")
			== "save_blocked_active_battle",
			"SaveService should return a stable active-battle rejection"
		)
		_finish_test_battle(session, map_scene)
		var direct_result := result_holder.get("result") as BattleResult
		_expect(
			direct_result != null
			and direct_result.is_victory()
			and direct_result.committed
			and not map_scene.has_active_battle()
			and map_scene.player_3d.interaction_enabled,
			"map-local Victory should commit once and restore exploration control"
		)
		var story_source := &"encounter.test.story_source"
		var battle_event := BattleTriggerEvent.new()
		battle_event.encounter = _test_encounter()
		var binding := StoryBinding.new()
		binding.event = battle_event
		binding.trigger_id = &"default"
		map_scene.battle_started.connect(_finish_test_battle.bind(map_scene), CONNECT_ONE_SHOT)
		await game_root.story_director.run_binding(
			binding,
			StoryOrigin.create(map_scene.map_id, story_source),
			map_scene
		)
		_expect(
			game_root.game_run.world.is_completed(map_scene.map_id, story_source)
			and not game_root.story_director.is_busy()
			and map_scene.player_3d.control_enabled
			and map_scene.player_3d.interaction_enabled
			and game_root.scene_stack.scene_count() == 1,
			"StoryDirector should await map combat, complete the source, and restore its lock"
		)
		var unhandled_event := UnhandledBattleTestEvent.new()
		unhandled_event.encounter = _test_encounter()
		var unhandled_binding := StoryBinding.new()
		unhandled_binding.event = unhandled_event
		unhandled_binding.trigger_id = &"default"
		var blocked_holder: Dictionary = {}
		game_root.story_director.control_restore_blocked.connect(
			func(reason: String) -> void: blocked_holder["reason"] = reason,
			CONNECT_ONE_SHOT
		)
		map_scene.battle_started.connect(_defeat_test_player.bind(map_scene), CONNECT_ONE_SHOT)
		await game_root.story_director.run_binding(
			unhandled_binding,
			StoryOrigin.create(map_scene.map_id, &"encounter.test.unhandled"),
			map_scene
		)
		_expect(
			String(blocked_holder.get("reason", "")).contains("Defeat"),
			"an unhandled Defeat should emit a stable control-lock diagnostic"
		)
		_expect(
			not map_scene.player_3d.control_enabled and not map_scene.player_3d.interaction_enabled,
			"an unhandled Defeat should keep exploration control locked"
		)
		for actor_state: ActorState in game_root.game_run.party.members:
			var actor_definition := game_root.content_database.actor(actor_state.definition_id)
			if actor_definition != null:
				actor_state.hp = CultivationRules.max_hp(
					actor_definition,
					actor_state,
					game_root.content_database
				)
				actor_state.mp = CultivationRules.max_mp(
					actor_definition,
					actor_state,
					game_root.content_database
				)
		map_scene.set_player_control_enabled(true)
	var shop := game_root.content_database.map(&"map.roadside.shop")
	game_root.travel_to(shop, shop.default_spawn_id)
	await process_frame
	await process_frame
	map_scene = game_root.scene_stack.current_scene() as MapGameScene3D
	if map_scene != null:
		_expect(
			await _wait_for_navigation_ready(map_scene.player_3d),
			"shop navigation map should synchronize before pointer input"
		)
		var shopkeeper := map_scene.get_node(^"WorldRoot/Shopkeeper") as NpcCharacter3D
		map_scene._update_camera(0.0)
		var ground_target := map_scene.player_3d.global_position + Vector3(2.5, 0.0, 0.8)
		var ground_press := _mouse_button_event(
			map_scene.camera_3d.unproject_position(ground_target),
			true
		)
		map_scene._unhandled_input(ground_press)
		_expect(
			map_scene.player_3d.is_navigating()
			and map_scene.player_3d.navigation_target_position().distance_to(
				Vector3(ground_target.x, map_scene.player_3d.global_position.y, ground_target.z)
			) < 0.4,
			"left-clicking open ground should start PlayerCharacter3D navigation"
		)
		map_scene._unhandled_input(_mouse_button_event(ground_press.position, false))
		Input.action_press(&"move_east")
		map_scene.player_3d._physics_process(BattleSession.FIXED_STEP_SECONDS)
		Input.action_release(&"move_east")
		var player_animation := map_scene.player_3d.get("_animation_player") as AnimationPlayer
		_expect(
			not map_scene.player_3d.is_navigating()
			and map_scene.player_3d.get("_current_animation") == &"run"
			and player_animation != null
			and String(player_animation.current_animation).get_file() == "run",
			"direct WASD input should cancel pointer navigation and enter the run pose, got %s"
			% [[
				map_scene.player_3d.get("_current_animation"),
				player_animation.get_animation_list() if player_animation != null else [],
			]]
		)
		map_scene.player_3d._physics_process(BattleSession.FIXED_STEP_SECONDS)
		_expect(
			map_scene.player_3d.get("_current_animation") == &"idle"
			and String(player_animation.current_animation).get_file() == "idle",
			"stopping direct movement should return the traveler to the relaxed idle pose"
		)
		map_scene.player_3d.position = shopkeeper.position + Vector3(-1.5, 0, 0)
		map_scene._update_camera(0.0)
		var shopkeeper_interactable := shopkeeper.get_node(^"Interactable") as StoryInteractable3D
		_expect(
			shopkeeper_interactable.get_collision_layer_value(
				PointerTarget3D.POINTER_COLLISION_LAYER
			),
			"StoryInteractable3D should expose a physics pointer target layer"
		)
		_expect(
			map_scene.player_3d.navigate_to(Vector3(500.0, 0.0, 500.0))
			== PlayerCharacter3D.NavigationStartResult.UNREACHABLE,
			"navigation should reject destinations too far from the navigation surface"
		)
		map_scene.set("_pointer_interactable", shopkeeper_interactable)
		map_scene._on_player_navigation_failed(
			Vector3(500.0, 0.0, 500.0),
			PlayerCharacter3D.NavigationFailure.STALLED
		)
		_expect(
			map_scene.pointer_feedback.failure_marker.visible
			and map_scene.pointer_feedback.failure_label.visible
			and map_scene.map_hud.feedback_label.visible
			and map_scene.map_hud.feedback_label.text == "无法到达"
			and map_scene.get("_pointer_interactable") == null
			and not map_scene.player_3d.is_navigating(),
			"interrupted pointer navigation should clear intent and show world plus HUD feedback"
		)
		var interact_press := _mouse_button_event(
			map_scene.camera_3d.unproject_position(
				shopkeeper_interactable.global_position + Vector3.UP * 0.65
			),
			true
		)
		map_scene._unhandled_input(interact_press)
		map_scene._update_pointer_intent()
		await process_frame
		_expect(
			game_root.dialogue_layer.is_active(),
			"left-clicking a nearby NPC should open its formal dialogue"
		)
		map_scene._unhandled_input(_mouse_button_event(interact_press.position, false))
		while game_root.story_director.is_busy():
			if game_root.dialogue_layer.is_waiting_for_option():
				game_root.dialogue_layer.option_selected.emit(&"later")
			elif game_root.dialogue_layer.is_active():
				game_root.dialogue_layer.advance_requested.emit()
			await process_frame
		_expect(not game_root.story_director.is_busy(), "dialogue should restore player control")
		map_scene.capture_location()
		game_root.scene_stack.push(game_root.menu_scene)
		await process_frame
		_expect(game_root.scene_stack.scene_count() == 2, "menu should push over the map")
		game_root.scene_stack.pop()
		await process_frame
		_expect(game_root.scene_stack.current_scene() == map_scene, "menu should return to map")
	var combat_map := game_root.content_database.map(&"map.roadside.north_slope_pack")
	game_root.travel_to(combat_map, combat_map.default_spawn_id)
	await process_frame
	await process_frame
	var combat_scene := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		combat_scene != null
		and combat_scene.player_3d != null
		and combat_scene.camera_3d.projection == Camera3D.PROJECTION_ORTHOGONAL
		and combat_scene.enemy_views().size() == 3,
		"formal 3D map should compose the fixed camera, player, and finite enemy group"
	)
	if combat_scene != null:
		var source := combat_scene.get_node(
			^"WorldRoot/EncounterSources/NorthSlopePackSource"
		) as EncounterSource3D
		combat_scene.set("_active_source", source)
		source.triggering = true
		var session := combat_scene.begin_battle(source.encounter)
		_expect(
			await _wait_for_navigation_ready(combat_scene.player_3d),
			"combat navigation map should synchronize before pointer input"
		)
		_expect(
			session != null
			and combat_scene.has_active_battle()
			and combat_scene.battle_hud.visible,
			"formal 3D encounter should bind the map-owned BattleSession and HUD"
		)
		var basic_key_label := combat_scene.map_hud.get_node(
			^"BattlePanel/ActionBar/Margin/Slots/Basic/Rows/Key"
		) as Label
		var skill_one_key_label := combat_scene.map_hud.get_node(
			^"BattlePanel/ActionBar/Margin/Slots/SkillOne/Rows/Key"
		) as Label
		combat_scene._refresh_battle_hud()
		_expect(
			basic_key_label.text == "鼠左"
			and skill_one_key_label.text == "鼠右"
			and not combat_scene.map_hud.interaction_panel.visible,
			"keyboard/mouse battle HUD should show only its current device labels"
		)
		var device_gamepad := InputEventJoypadButton.new()
		device_gamepad.button_index = JOY_BUTTON_A
		device_gamepad.pressed = true
		combat_scene._input(device_gamepad)
		combat_scene._refresh_battle_hud()
		_expect(
			basic_key_label.text == "A" and skill_one_key_label.text == "X",
			"gamepad input should atomically replace keyboard/mouse action labels"
		)
		var device_keyboard := InputEventKey.new()
		device_keyboard.physical_keycode = KEY_W
		device_keyboard.pressed = true
		combat_scene._input(device_keyboard)
		combat_scene._refresh_battle_hud()
		_expect(
			basic_key_label.text == "鼠左" and skill_one_key_label.text == "鼠右",
			"keyboard input should restore keyboard/mouse labels without mixed prompts"
		)
		var pointer_enemy := source.enemy_views[0]
		var combat_player_animation := combat_scene.player_3d.get(
			"_animation_player"
		) as AnimationPlayer
		var feedback_request := combat_scene.request_battle_action(
			BattleActionIntent.basic_attack(session.player.id, pointer_enemy.actor_id)
		)
		for _step: int in range(120):
			if (
				session.player.current_action != null
				and session.player.current_action.phase == BattleActionState.Phase.ACTIVE
			):
				break
			combat_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		combat_scene.resolve_battle_hit(
			session.player.id,
			feedback_request.action_instance_id,
			pointer_enemy.actor_id
		)
		_expect(
			feedback_request.accepted()
			and combat_scene.is_hit_stop_active()
			and combat_scene.combat_feedback.active_effect_count() >= 2
			and combat_scene.player_3d.get("_current_animation") == &"attack"
			and combat_player_animation != null
			and String(combat_player_animation.current_animation).get_file() == "attack",
			"confirmed damage should create local hit-stop, sword arc, hit spark, and flash feedback; pose=%s"
			% [combat_scene.player_3d.get("_current_animation")]
		)
		combat_scene._process(0.2)
		game_root.settings_service.set_accessibility(48.0, true, false)
		combat_scene._start_hit_stop(MapGameScene3D.ENEMY_HIT_STOP_SECONDS)
		_expect(
			is_equal_approx(
				float(combat_scene.get("_hit_stop_remaining")),
				MapGameScene3D.ENEMY_HIT_STOP_SECONDS
				* MapGameScene3D.REDUCED_HIT_STOP_SCALE
			),
			"reduced-flash mode should retain readable but shortened local hit-stop"
		)
		combat_scene._restore_hit_stop_motion()
		var transient_motion := Node.new()
		combat_scene.add_child(transient_motion)
		transient_motion.add_to_group(&"battle_motion_3d")
		transient_motion.set_physics_process(true)
		combat_scene._start_hit_stop(MapGameScene3D.ENEMY_HIT_STOP_SECONDS)
		transient_motion.free()
		combat_scene._restore_hit_stop_motion()
		_expect(
			not combat_scene.is_hit_stop_active()
			and (combat_scene.get("_hit_stop_physics_states") as Array).is_empty(),
			"hit-stop restoration should ignore battle motion freed before the pause ends"
		)
		game_root.settings_service.set_accessibility(48.0, false, false)
		while session.player.current_action != null:
			combat_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		_expect(
			combat_scene.player_3d.get("_current_animation") == &"idle"
			and String(combat_player_animation.current_animation).get_file() == "idle",
			"finished player attacks should recover directly to idle"
		)
		var visual_event := BattleEvent.new()
		visual_event.kind = BattleEvent.Kind.ACTION_STARTED
		visual_event.actor_id = session.player.id
		visual_event.action_id = &"skill.test.cast"
		combat_scene.player_3d.handle_battle_event(visual_event)
		_expect(
			combat_scene.player_3d.get("_current_animation") == &"cast"
			and String(combat_player_animation.current_animation).get_file() == "cast",
			"skill actions should enter the cast animation instead of a binding pose, got %s"
			% [combat_scene.player_3d.get("_current_animation")]
		)
		visual_event = BattleEvent.new()
		visual_event.kind = BattleEvent.Kind.DAMAGE
		visual_event.target_id = session.player.id
		combat_scene.player_3d.handle_battle_event(visual_event)
		_expect(
			combat_scene.player_3d.get("_current_animation") == &"hit"
			and String(combat_player_animation.current_animation).get_file() == "hit",
			"player damage should enter the hit animation"
		)
		visual_event = BattleEvent.new()
		visual_event.kind = BattleEvent.Kind.DEATH
		visual_event.actor_id = session.player.id
		combat_scene.player_3d.handle_battle_event(visual_event)
		_expect(
			combat_scene.player_3d.get("_current_animation") == &"death"
			and String(combat_player_animation.current_animation).get_file() == "death",
			"player death should enter the death animation"
		)
		visual_event = BattleEvent.new()
		visual_event.kind = BattleEvent.Kind.ACTION_FINISHED
		visual_event.actor_id = session.player.id
		combat_scene.player_3d.handle_battle_event(visual_event)
		_expect(
			combat_scene.player_3d.get("_current_animation") == &"idle",
			"visual recovery should return to idle without exposing the bind pose"
		)
		var telegraph_enemy := source.enemy_views[1]
		var telegraph_actor := session.actor(telegraph_enemy.actor_id)
		var telegraph_request := combat_scene.request_battle_action(
			BattleActionIntent.basic_attack(telegraph_actor.id, session.player.id)
		)
		var enemy_animation := telegraph_enemy.get("_animation_player") as AnimationPlayer
		var expected_enemy_animation := (
			"cast"
			if telegraph_enemy.definition.combat_style
			== EnemyDefinition.CombatStyle.RANGED
			else "attack"
		)
		_expect(
			telegraph_request.accepted()
			and telegraph_enemy.telegraph.visible
			and telegraph_enemy.telegraph.scale.length() > 0.1
			and telegraph_enemy.get("_current_animation") == (
				&"cast"
				if telegraph_enemy.definition.combat_style
				== EnemyDefinition.CombatStyle.RANGED
				else &"attack"
			)
			and enemy_animation != null
			and String(enemy_animation.current_animation).get_file()
			== expected_enemy_animation,
			"enemy windup should expose a visible animated world-space telegraph"
		)
		while telegraph_actor.current_action != null:
			combat_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		combat_scene.player_3d.global_position = (
			pointer_enemy.global_position + Vector3(4.0, 0.0, 0.0)
		)
		combat_scene._update_camera(0.0)
		var target_switch := InputEventAction.new()
		target_switch.action = &"combat_target_next"
		target_switch.pressed = true
		combat_scene._unhandled_input(target_switch)
		var first_soft_target := combat_scene.get("_soft_target") as EnemyActorView3D
		combat_scene._unhandled_input(target_switch)
		var second_soft_target := combat_scene.get("_soft_target") as EnemyActorView3D
		_expect(
			first_soft_target != null
			and second_soft_target != null
			and first_soft_target != second_soft_target
			and combat_scene.pointer_feedback.target_ring.visible,
			"target-switch input should cycle visible enemies and keep a world target ring"
		)
		combat_scene.set("_pointer_enemy", null)
		combat_scene._update_camera(0.0)
		var combat_camera_focus := combat_scene.get("_camera_focus") as Vector3
		var target_camera_offset := (
			second_soft_target.global_position - combat_scene.player_3d.global_position
		)
		target_camera_offset.y = 0.0
		var expected_camera_focus := combat_scene.player_3d.global_position + (
			target_camera_offset.normalized()
			* minf(target_camera_offset.length() * 0.6, 3.2)
		)
		_expect(
			combat_camera_focus.distance_to(expected_camera_focus) < 0.01,
			"combat camera should bias toward the active target to keep both actors visible"
		)
		var enemy_screen_position := combat_scene.camera_3d.unproject_position(
			pointer_enemy.global_position + Vector3.UP * 0.85
		)
		var enemy_press := _mouse_button_event(enemy_screen_position, true)
		combat_scene._input(enemy_press)
		combat_scene._unhandled_input(enemy_press)
		combat_scene._update_pointer_intent()
		combat_scene._refresh_battle_hud()
		_expect(
			combat_scene.player_3d.is_navigating()
			and session.player.current_action == null
			and combat_scene.pointer_feedback.target_ring.visible
			and combat_scene.map_hud.target_panel.visible
			and combat_scene.map_hud.target_name_label.text
			== pointer_enemy.definition.display_name,
			"left-clicking a distant enemy should chase it before attacking"
		)
		combat_scene.player_3d.global_position = (
			pointer_enemy.global_position + Vector3(1.0, 0.0, 0.0)
		)
		combat_scene._update_pointer_intent()
		_expect(
			session.player.current_action != null
			and session.player.current_action.action_id == BattleSession.BASIC_ATTACK_ID,
			"pointer pursuit should issue one basic attack after entering range"
		)
		combat_scene._unhandled_input(_mouse_button_event(enemy_screen_position, false))
		for _step: int in range(90):
			if session.player.current_action == null:
				break
			combat_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		combat_scene.player_3d.global_position = (
			pointer_enemy.global_position + Vector3(4.0, 0.0, 0.0)
		)
		combat_scene._update_camera(0.0)
		enemy_screen_position = combat_scene.camera_3d.unproject_position(
			pointer_enemy.global_position + Vector3.UP * 0.85
		)
		var force_move_ground: Variant = combat_scene._screen_ground_point(
			enemy_screen_position
		)
		var force_move_press := _mouse_button_event(enemy_screen_position, true, false, true)
		combat_scene._unhandled_input(force_move_press)
		combat_scene._update_pointer_intent()
		_expect(
			combat_scene.player_3d.is_navigating()
			and session.player.current_action == null
			and force_move_ground is Vector3
			and combat_scene.player_3d.navigation_target_position().distance_to(
				Vector3(
					(force_move_ground as Vector3).x,
					combat_scene.player_3d.global_position.y,
					(force_move_ground as Vector3).z
				)
			) < 0.4,
			"Ctrl plus left-click should force movement even over an enemy"
		)
		combat_scene._unhandled_input(
			_mouse_button_event(force_move_press.position, false, false, true)
		)
		var stand_attack_press := _mouse_button_event(
			enemy_screen_position,
			true,
			true
		)
		combat_scene._unhandled_input(stand_attack_press)
		combat_scene._update_pointer_intent()
		_expect(
			not combat_scene.player_3d.is_navigating()
			and session.player.current_action != null
			and session.player.current_action.action_id == BattleSession.BASIC_ATTACK_ID,
			"Shift plus left-click should attack in place without chasing"
		)
		combat_scene._unhandled_input(
			_mouse_button_event(stand_attack_press.position, false, true)
		)
		for _step: int in range(90):
			if session.player.current_action == null:
				break
			combat_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		var gamepad_attack := InputEventJoypadButton.new()
		gamepad_attack.button_index = JOY_BUTTON_A
		gamepad_attack.pressed = true
		combat_scene.player_3d._unhandled_input(gamepad_attack)
		_expect(
			session.player.current_action != null
			and session.player.current_action.action_id == BattleSession.BASIC_ATTACK_ID,
			"formal gamepad mapping should request the same typed combat action"
		)
		var views_active := true
		for enemy_view: EnemyActorView3D in source.enemy_views:
			views_active = views_active and enemy_view.state == EnemyActorView3D.State.ACTIVE
		_expect(views_active, "formal enemy views should bind the same BattleSession")
		var escaped_result := combat_scene.escape_battle()
		_expect(
			escaped_result.outcome == BattleResult.Outcome.ESCAPED
			and not game_root.game_run.world.is_completed(
				combat_scene.map_id,
				source.persistent_id
			)
			and source.all_living_enemies_home()
			and not combat_scene.player_3d.is_navigating()
			and not combat_scene.pointer_feedback.target_ring.visible
			and not combat_scene.map_hud.target_panel.visible
			and combat_scene.get("_pointer_enemy") == null
			and combat_scene.get("_soft_target") == null,
			"Escaped should keep the source while clearing navigation, target, pointer, and HUD state"
		)
	var leader := game_root.game_run.party.leader()
	CultivationRules.gain_cultivation(leader, 230, game_root.content_database)
	var catalyst := game_root.content_database.item(
		&"item.roadside.qi_eating_stone_heart"
	)
	game_root.game_run.inventory.add_item(catalyst, 1)
	var breakthrough := CultivationTransaction.breakthrough(
		game_root.game_run,
		game_root.content_database.foundation(&"foundation.sharp_metal"),
		catalyst,
		game_root.content_database
	)
	_expect(breakthrough.succeeded(), "GameRoot smoke should prepare a valid foundation build")
	var lantern_map := game_root.content_database.map(&"map.roadside.lantern_pass")
	game_root.travel_to(lantern_map, &"from_wilds")
	await process_frame
	await process_frame
	var lantern_scene := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		lantern_scene != null
		and lantern_scene.map_id == lantern_map.id
		and lantern_scene.story_module is LanternPassStory
		and lantern_scene.get_node(^"WorldRoot/EncounterSources").get_child_count() == 6
		and lantern_scene.enemy_views().size() == 38
		and lantern_scene.get_node_or_null(^"WorldRoot/Terrain/PineSouthEast") is StaticBody3D
		and lantern_scene.get_node_or_null(^"WorldRoot/Terrain/PineFinalWest") is StaticBody3D
		and lantern_scene.get_node_or_null(^"WorldRoot/SpawnPoints/from_wilds") is Marker3D
		and lantern_scene.get_node_or_null(^"WorldRoot/NavigationRegion3D") is NavigationRegion3D,
		"lantern pass should compose six encounters, roadside dressing, paired spawn, and navigation"
	)
	if lantern_scene != null:
		_expect(
			await _wait_for_navigation_ready(lantern_scene.player_3d),
			"lantern-pass navigation map should synchronize before route checks"
		)
		var navigation_map := lantern_scene.player_3d.navigation_agent.get_navigation_map()
		for source_name: StringName in [
			&"FirstPack", &"StoneBeast", &"FoundationFinalTest",
		]:
			var route_target := lantern_scene.get_node(
				NodePath("WorldRoot/EncounterSources/%s" % source_name)
			) as Node3D
			var route := NavigationServer3D.map_get_path(
				navigation_map,
				lantern_scene.player_3d.global_position,
				route_target.global_position,
				true,
				lantern_scene.player_3d.navigation_agent.navigation_layers
			)
			_expect(
				not route.is_empty()
				and route[route.size() - 1].distance_to(route_target.global_position) < 0.4,
				"lantern-pass navigation should connect from_wilds to %s" % source_name
			)
		var boss_source := lantern_scene.get_node(
			^"WorldRoot/EncounterSources/StoneBeast"
		) as EncounterSource3D
		lantern_scene.set("_active_source", boss_source)
		boss_source.triggering = true
		var boss_session := lantern_scene.begin_battle(boss_source.encounter)
		lantern_scene._refresh_battle_hud()
		_expect(
			lantern_scene.map_hud.target_panel.visible
			and lantern_scene.map_hud.target_type_label.text == "首领"
			and lantern_scene.map_hud.target_hp_bar.max_value
			== boss_session.enemies[0].max_hp,
			"single charger encounters should expose a persistent boss health card"
		)
		var ultimate_input := InputEventAction.new()
		ultimate_input.action = &"combat_skill_three"
		ultimate_input.pressed = true
		lantern_scene.player_3d._unhandled_input(ultimate_input)
		_expect(
			boss_session.player.current_action != null
			and boss_session.player.current_action.action_id
			== &"skill.roadside.origin_sword_array",
			"foundation establishment should expose its third-slot ultimate in real map input"
		)
		while boss_session.player.current_action != null:
			lantern_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		var boss_actor := boss_session.enemies[0]
		var charge := lantern_scene.request_battle_action(
			BattleActionIntent.charge(boss_actor.id, boss_session.player.id)
		)
		for _step: int in range(120):
			if (
				boss_actor.current_action != null
				and boss_actor.current_action.phase == BattleActionState.Phase.ACTIVE
			):
				break
			lantern_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		var pillar_events := lantern_scene.resolve_battle_pillar_contact(
			boss_actor.id,
			charge.action_instance_id,
			&"pillar.west"
		)
		_expect(
			boss_session.is_pillar_used(&"pillar.west")
			and boss_actor.stagger_remaining_seconds > 0.0
			and not pillar_events.is_empty(),
			"formal lantern Boss should enter fixed-step stagger after an active pillar collision"
		)
		lantern_scene.escape_battle()
	game_root._unhandled_input(open_menu)
	await process_frame
	var final_menu := game_root.scene_stack.current_scene() as MenuGameScene
	if final_menu != null:
		final_menu._return_to_title()
	await process_frame
	_expect(
		game_root.scene_stack.current_scene() is TitleGameScene
		and game_root.scene_stack.scene_count() == 1,
		"system menu should reset the scene stack back to the title"
	)
	game_root.queue_free()
	await process_frame


func _capture_dialogue_result(
	layer: DialogueLayer,
	dialogue: DialogueDefinition,
	block_id: StringName,
	holder: Dictionary
) -> void:
	holder["result"] = await layer.show_dialogue(dialogue, block_id)


func _capture_scene_stack_result(stack: GameSceneStack, scene: PackedScene) -> void:
	_scene_stack_result_received = false
	_scene_stack_result = await stack.push(scene, {"name": "modal"})
	_scene_stack_result_received = true


func _pack_scene_stack_fixture() -> PackedScene:
	var instance := SceneStackTestScene.new()
	var packed := PackedScene.new()
	var error := packed.pack(instance)
	instance.free()
	_expect(error == OK, "SceneStack fixture should pack")
	return packed


func _test_encounter() -> BattleEncounter:
	var enemy := EnemyDefinition.new()
	enemy.id = &"enemy.test.map_melee"
	enemy.display_name = "Map Test Enemy"
	enemy.max_hp = 10
	enemy.attack = 5
	var entry := EncounterEnemy.new()
	entry.enemy = enemy
	entry.instance_id = &"enemy.test.map_01"
	var encounter := BattleEncounter.new()
	encounter.id = &"encounter.test.map_local"
	encounter.display_name = "Map Test Encounter"
	encounter.enemies.append(entry)
	return encounter


func _finish_test_battle(session: BattleSession, map_scene: MapGameScene) -> void:
	if session == null or map_scene == null or not map_scene.has_active_battle():
		return
	var request := map_scene.request_battle_action(
		BattleActionIntent.basic_attack(session.player.id)
	)
	_expect(request.accepted(), "map-local battle should accept the player's basic attack")
	for _step: int in range(120):
		if (
			session.player.current_action != null
			and session.player.current_action.phase == BattleActionState.Phase.ACTIVE
		):
			break
		map_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
	map_scene.resolve_battle_hit(
		session.player.id,
		request.action_instance_id,
		session.enemies[0].id
	)


func _defeat_test_player(session: BattleSession, map_scene: MapGameScene) -> void:
	if session == null or map_scene == null or not map_scene.has_active_battle():
		return
	session.player.hp = 1
	var enemy := session.enemies[0]
	var request := map_scene.request_battle_action(
		BattleActionIntent.basic_attack(enemy.id, session.player.id)
	)
	for _step: int in range(120):
		if (
			enemy.current_action != null
			and enemy.current_action.phase == BattleActionState.Phase.ACTIVE
		):
			break
		map_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
	map_scene.resolve_battle_hit(enemy.id, request.action_instance_id, session.player.id)


func _collect_framework_files(directory_path: String, result: PackedStringArray) -> void:
	var directory := DirAccess.open(directory_path)
	_expect(directory != null, "framework boundary check should open %s" % directory_path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		if file_name.get_extension().to_lower() in ["gd", "tscn", "tres"]:
			result.append(directory_path.path_join(file_name))
	for child_name: String in directory.get_directories():
		if not child_name.begins_with("."):
			_collect_framework_files(directory_path.path_join(child_name), result)


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_directory_if_empty(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _ensure_input_actions() -> void:
	for action: StringName in [
		&"move_north", &"move_south", &"move_west", &"move_east",
		&"aim_north", &"aim_south", &"aim_west", &"aim_east",
		&"interact", &"menu", &"combat_attack", &"combat_skill_one",
		&"combat_skill_two", &"combat_skill_three", &"combat_dodge", &"combat_item",
		&"combat_stand_ground", &"combat_force_move", &"combat_target_next",
	]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _mouse_button_event(
	position: Vector2,
	pressed: bool,
	shift_pressed: bool = false,
	ctrl_pressed: bool = false
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	event.ctrl_pressed = ctrl_pressed
	return event


func _wait_for_navigation_ready(player: PlayerCharacter3D) -> bool:
	for _physics_step: int in range(12):
		var navigation_map := player.navigation_agent.get_navigation_map()
		if navigation_map.is_valid():
			var closest := NavigationServer3D.map_get_closest_point(
				navigation_map,
				player.global_position
			)
			if closest.distance_to(player.global_position) <= PlayerCharacter3D.NAVIGATION_SNAP_LIMIT:
				return true
		await physics_frame
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
