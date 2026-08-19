extends SceneTree

const TEST_SAVE := "res://tests/.tmp_roadside_save.json"
const TEST_SLOTS := "res://tests/.tmp_roadside_slots"
const TEST_SETTINGS := "res://tests/.tmp_roadside_settings.cfg"
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
	await _test_battle_trigger_event()
	_test_random_state()
	_test_item_delivery()
	_test_battle_session()
	_test_game_run_round_trip()
	_test_save_service()
	_test_settings_service()
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
	_expect(database.npcs.size() == 1, "formal slice should register one original NPC")
	_expect(database.maps.size() == 4, "formal slice should register three gathering maps and the 3D combat map")
	_expect(database.items.size() == 2, "formal content should register gathering material and battle medicine")
	_expect(database.skills.size() == 2, "formal combat slice should register two original skills")
	_expect(database.statuses.size() == 1, "formal combat slice should register one timed status")
	_expect(database.enemies.size() == 2, "formal combat slice should register melee and ranged enemies")
	_expect(database.encounters.size() == 1, "formal combat slice should register one finite encounter")
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
	_expect(scanned.get("stories", []).size() == 2, "formal story scan should include both roadside modules")
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
		"database should expose the large generated default map ID"
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
	layer.advance_requested.emit()
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
	_expect(
		ground != null
		and ground.get_used_cells().size() == 252
		and navigation != null
		and navigation.navigation_mesh.get_polygon_count() > 0,
		"3D roadside shop should bake its 18x14 ground and usable navigation"
	)
	_expect(
		shopkeeper != null
		and shopkeeper.definition != null
		and shopkeeper.definition.id == &"npc.roadside.shopkeeper"
		and interactable != null
		and interactable.trigger_id == &"talk_shopkeeper"
		and interactable.actor_definition_id == &"npc.roadside.shopkeeper",
		"3D shopkeeper definition, gathering trigger, and story origin actor ID should agree"
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
		and shop_portal.portal_target_spawn_id == &"default"
		and pack_portal.portal_target_map_id == &"map.roadside.north_slope_pack"
		and pack_portal.portal_target_spawn_id == &"safe_entry",
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
	var wilds := game_root.scene_stack.current_scene() as MapGameScene3D
	_interact_3d(wilds, ^"WorldRoot/TrailToShop/Interactable")
	await _drive_story_ui(game_root, [])
	var shop := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		shop != null and shop.map_id == &"map.roadside.shop",
		"3D wilds portal should enter the shop through stable map and spawn IDs"
	)
	_interact_3d(shop, ^"WorldRoot/Shopkeeper/Interactable")
	await _drive_story_ui(game_root, [&"accept", &"safe_route"])
	var herb_slope := game_root.scene_stack.current_scene() as MapGameScene3D
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
	var restored := GameRun.from_dictionary(run.to_dictionary())
	_expect(restored != null, "GameRun should round-trip the new content version")
	if restored == null:
		return
	_expect(
		restored.party.leader_id == &"actor.roadside.traveler",
		"GameRun should preserve the original traveler"
	)
	_expect(restored.location.map_id == &"map.roadside.shop", "location should round-trip")
	_expect(restored.location.position == Vector3(48, 3, 192), "exact 3D position should round-trip")
	var legacy_data := run.to_dictionary()
	legacy_data["save_version"] = GameRun.PREVIOUS_SAVE_VERSION
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
	legacy_data["save_version"] = GameRun.PREVIOUS_SAVE_VERSION
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
	_expect(service.locale == &"en", "settings should persist locale choice")
	_expect(service.key_for_action(&"interact") == KEY_E, "settings should rebind interact")
	service.set_locale(&"zh_CN", false)
	_remove_if_exists(TEST_SETTINGS)
	root.queue_free()


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
		map_scene != null and map_scene.map_id == &"map.roadside.north_slope_wilds",
		"new game should enter the large generated 3D north slope wilds"
	)
	_expect(
		map_scene != null
		and (
			map_scene.get_node(^"WorldRoot/Terrain/GeneratedGroundGrid") as GridMap
		).get_used_cells().size() == 2048,
		"new game default should expose the baked 64x32 3D map"
	)
	_expect(InputMap.has_action(&"toggle_fullscreen"), "F11 fullscreen action should be registered")
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
				actor_state.hp = actor_definition.base_max_hp
				actor_state.mp = actor_definition.base_max_mp
		map_scene.set_player_control_enabled(true)
	var shop := game_root.content_database.map(&"map.roadside.shop")
	game_root.travel_to(shop, shop.default_spawn_id)
	await process_frame
	await process_frame
	map_scene = game_root.scene_stack.current_scene() as MapGameScene3D
	if map_scene != null:
		var shopkeeper := map_scene.get_node(^"WorldRoot/Shopkeeper") as NpcCharacter3D
		map_scene.player_3d.position = shopkeeper.position + Vector3(-1.5, 0, 0)
		map_scene._on_player_interact_3d()
		await process_frame
		_expect(game_root.dialogue_layer.is_active(), "shopkeeper should open formal dialogue")
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
			session != null
			and combat_scene.has_active_battle()
			and combat_scene.battle_hud.visible,
			"formal 3D encounter should bind the map-owned BattleSession and HUD"
		)
		var keyboard_attack := InputEventAction.new()
		keyboard_attack.action = &"combat_attack"
		keyboard_attack.pressed = true
		combat_scene.player_3d._unhandled_input(keyboard_attack)
		_expect(
			session.player.current_action != null
			and session.player.current_action.action_id == BattleSession.BASIC_ATTACK_ID,
			"formal keyboard combat input should request the map-owned action"
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
			and source.all_living_enemies_home(),
			"Escaped should keep the persistent source and reset its enemy views"
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
		&"combat_skill_two", &"combat_dodge", &"combat_item",
	]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
