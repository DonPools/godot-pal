extends SceneTree

const TEST_SAVE := "res://tests/.tmp_roadside_save.json"
const TEST_SLOTS := "res://tests/.tmp_roadside_slots"
const TEST_SETTINGS := "res://tests/.tmp_roadside_settings.cfg"
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
	_test_directional_frames()
	await _test_dialogue_options()
	await _test_roadside_scene()
	await _test_herb_slope_scene()
	await _test_gathering_story()
	_test_random_state()
	_test_item_delivery()
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
		viewport_width == 320 and viewport_height == 180,
		"formal slice should use a 320x180 internal viewport, got %dx%d"
		% [viewport_width, viewport_height]
	)
	_expect(
		window_width == 960 and window_height == 540,
		"default window should be an exact 3x presentation, got %dx%d"
		% [window_width, window_height]
	)
	_expect(
		ProjectSettings.get_setting("display/window/stretch/aspect") == "keep",
		"viewport presentation should preserve the 16:9 aspect ratio"
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
	_expect(database.maps.size() == 2, "gathering slice should register shop and herb slope")
	_expect(database.items.size() == 1, "gathering slice should register one material")
	_expect(database.skills.is_empty(), "formal slice should not keep obsolete lab skills")
	_expect(database.enemies.is_empty(), "formal slice should not keep obsolete lab enemies")
	_expect(database.shops.is_empty(), "formal slice should not keep obsolete lab shops")
	_expect(
		database.story_directories == PackedStringArray(["res://game/roadside/stories"]),
		"formal content should scan only the roadside story directory"
	)
	var scanned := ContentSourceScanner.new().scan_story_resources(database.story_directories)
	_expect(scanned.get("diagnostics", []).is_empty(), "configured story directory should scan cleanly")
	_expect(scanned.get("stories", []).size() == 1, "formal story scan should exclude legacy lab stories")
	_expect(
		database.actor(&"actor.roadside.traveler") != null,
		"database should expose the original traveler ID"
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
		database.item(&"item.roadside.fanqing_grass") != null,
		"database should expose the gathering material ID"
	)


func _test_original_assets() -> void:
	var diagnostics := AssetLibrary.validate_assets()
	_expect(diagnostics.is_empty(), "required original assets should exist: %s" % [diagnostics])
	for path: String in AssetLibrary.REQUIRED_ASSETS:
		_expect(not path.begins_with("res://generated/"), "runtime assets must not use generated/")


func _test_directional_frames() -> void:
	var actor := load("res://content/actors/traveler.tres") as ActorDefinition
	_expect(
		actor.field_sprite != null and actor.field_sprite.get_size() == Vector2(72, 128),
		"traveler should use a strict 3x4 sheet of 24x32 frames"
	)
	var frames := DirectionalSpriteFrames.from_3x4_sheet(actor.field_sprite)
	for direction: StringName in DirectionalSpriteFrames.DIRECTIONS:
		_expect(frames.has_animation(direction), "traveler should expose %s" % direction)
		_expect(
			frames.get_frame_count(direction) == 4,
			"%s should play stand-step-stand-step" % direction
		)
		var frame := frames.get_frame_texture(direction, 0) as AtlasTexture
		_expect(
			frame != null and frame.region.size == Vector2(24, 32),
			"%s should crop exact 24x32 cells" % direction
		)


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
	var holder: Dictionary = {}
	_capture_dialogue_result(layer, dialogue, &"route_choice", holder)
	await process_frame
	layer.advance_requested.emit()
	await process_frame
	_expect(layer.is_waiting_for_option(), "dialogue should wait for a typed option")
	layer.option_selected.emit(&"safe_route")
	await process_frame
	var result := holder.get("result") as DialogueResult
	_expect(
		result != null and result.selected_option_id == &"safe_route",
		"dialogue should return the selected semantic option ID"
	)
	layer.queue_free()
	await process_frame


func _test_roadside_scene() -> void:
	var packed := load("res://game/roadside/maps/roadside_shop.tscn") as PackedScene
	var scene := packed.instantiate() as MapGameScene
	get_root().add_child(scene)
	await process_frame
	_expect(scene != null, "roadside shop should instantiate as MapGameScene")
	_expect(
		scene.ground_layer.tile_set.tile_size == Vector2i(32, 16)
		and scene.ground_layer.tile_set.tile_shape == TileSet.TILE_SHAPE_ISOMETRIC,
		"roadside shop should use strict 32x16 diamond tiles"
	)
	_expect(
		scene.ground_layer.get_used_cells().size() == 252,
		"roadside shop should store its expanded 18x14 layout in TileMapLayer"
	)
	_expect(
		scene.ground_layer.get_used_rect().size == Vector2i(18, 14),
		"roadside shop should expose an exact 18x14 ground rectangle"
	)
	_expect(scene.y_sort_root.y_sort_enabled, "roadside people and props should share YSort")
	var player_camera := scene.player.get_node(^"CameraRig") as Camera2D
	var fixed_camera := scene.get_node(^"FixedCamera") as Camera2D
	_expect(
		player_camera.enabled and not fixed_camera.enabled,
		"the smaller viewport should follow the player instead of showing the whole map"
	)
	var tree := scene.get_node(^"YSortRoot/PineTree") as StaticBody2D
	var shopkeeper := scene.get_node(^"YSortRoot/Shopkeeper") as NpcCharacter
	_expect(
		shopkeeper.sprite_sheet != null
		and shopkeeper.sprite_sheet.get_size() == Vector2(72, 128),
		"shopkeeper should use a matching original 3x4 sheet"
	)
	var interactable := shopkeeper.get_node(^"Interactable") as Interactable
	_expect(
		interactable.event == null and interactable.trigger_id == &"talk_shopkeeper",
		"shopkeeper should bind the multi-stage gathering StoryModule"
	)
	scene.player.position = Vector2(0, 96)
	var collision := scene.player.move_and_collide(Vector2(0, -32))
	_expect(
		collision != null and collision.get_collider() == tree,
		"tree should physically stop player movement"
	)
	scene.queue_free()
	await process_frame


func _test_herb_slope_scene() -> void:
	var packed := load("res://game/roadside/maps/herb_slope.tscn") as PackedScene
	var scene := packed.instantiate() as MapGameScene
	get_root().add_child(scene)
	await process_frame
	_expect(scene.ground_layer.get_used_cells().size() == 252, "herb slope should reuse strict TileMap ground")
	_expect(scene.y_sort_root.y_sort_enabled, "herbs, trees, and player should share YSort")
	var patch := scene.get_node(^"YSortRoot/HerbWest") as HarvestPatch
	var run := GameRun.new()
	patch.configure(run, &"map.roadside.herb_slope")
	_expect(patch.visual.texture == patch.texture, "fresh herb patch should show its full plant")
	run.flags.set_value(RoadsideGatheringStory.FIRST_WEST)
	patch.refresh()
	_expect(
		patch.visual.texture == patch.harvested_texture
		and patch.interactable.process_mode == Node.PROCESS_MODE_DISABLED,
		"leave-root harvest should show a cut, unavailable patch for the current trip"
	)
	run.flags.set_value(RoadsideGatheringStory.SECOND_TRIP_STARTED)
	patch.refresh()
	_expect(
		patch.visual.texture == patch.texture
		and patch.interactable.process_mode == Node.PROCESS_MODE_INHERIT,
		"a leave-root patch should regrow for the second trip"
	)
	var portal := scene.get_node(^"YSortRoot/TrailBack/Interactable") as Interactable
	_expect(
		portal.portal_target_map_id == &"map.roadside.shop"
		and portal.portal_target_spawn_id == &"from_slope",
		"herb slope should return through a semantic portal"
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
	run.location.position = Vector2(24, 96)
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
	_expect(restored.location.position == Vector2(24, 96), "exact position should round-trip")
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
	var map_scene := game_root.scene_stack.current_scene() as MapGameScene
	_expect(
		map_scene != null and map_scene.map_id == &"map.roadside.shop",
		"new game should enter the formal roadside shop"
	)
	_expect(InputMap.has_action(&"toggle_fullscreen"), "F11 fullscreen action should be registered")
	if map_scene != null:
		var shopkeeper := map_scene.get_node(^"YSortRoot/Shopkeeper") as NpcCharacter
		map_scene.player.position = shopkeeper.position + Vector2(-24, 0)
		map_scene._on_player_interact()
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
		&"move_north", &"move_south", &"move_west", &"move_east", &"interact", &"menu",
	]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
