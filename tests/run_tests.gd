extends SceneTree

const TEST_SAVE := "user://framework_lab_test.json"
const FakeStoryContextClass := preload("res://tests/fake_story_context.gd")

var _failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_story_trace()
	_test_game_run_round_trip()
	_test_map_scene_content()
	await _test_scene_smoke()
	if _failures.is_empty():
		print("framework-lab tests passed")
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)


func _test_story_trace() -> void:
	var story := load("res://stories/lab/borrowed_umbrella.tres") as BorrowedUmbrellaStory
	var fake := FakeStoryContextClass.new()
	await story.run(&"enter_hall", fake)
	_expect(fake.stage == &"met_innkeeper", "entry should introduce the innkeeper")
	await story.run(&"talk_innkeeper", fake)
	_expect(fake.stage == &"looking_for_owner", "innkeeper should start the search")
	await story.run(&"enter_courtyard", fake)
	_expect(
		fake.flags.has(&"flag.story.lab.borrowed_umbrella.courtyard_seen"),
		"courtyard entry flag should be set"
	)
	await story.run(&"talk_traveler", fake)
	_expect(fake.stage == &"owner_found", "traveler should identify the umbrella")
	await story.run(&"take_umbrella", fake)
	_expect(fake.source_completed, "umbrella source should complete exactly once")
	_expect(fake.stage == &"umbrella_found", "umbrella interaction should advance the story")
	await story.run(&"talk_innkeeper", fake)
	_expect(fake.stage == &"completed", "returning the umbrella should finish the story")
	_expect(
		fake.shown_blocks == [
			&"opening",
			&"innkeeper_request",
			&"courtyard_first",
			&"traveler_reveal",
			&"umbrella_take",
			&"innkeeper_finish",
		],
		"story dialogue trace should remain deterministic"
	)


func _test_game_run_round_trip() -> void:
	var run := GameRun.new()
	run.story.set_stage(&"story.lab.borrowed_umbrella", &"owner_found")
	run.flags.set_value(&"flag.test")
	run.world.complete(&"map.lab.rain_courtyard", &"old_umbrella")
	run.location.map_id = &"map.lab.rain_courtyard"
	run.location.position = Vector2(12.0, 34.0)
	run.location.has_exact_position = true
	var restored := GameRun.from_dictionary(run.to_dictionary())
	_expect(restored != null, "GameRun should decode its own save payload")
	if restored == null:
		return
	_expect(
		restored.story.get_stage(&"story.lab.borrowed_umbrella", &"") == &"owner_found",
		"StoryState should round-trip"
	)
	_expect(restored.flags.is_set(&"flag.test"), "GameFlags should round-trip")
	_expect(
		restored.world.is_completed(&"map.lab.rain_courtyard", &"old_umbrella"),
		"WorldState should round-trip"
	)
	_expect(restored.location.position == Vector2(12.0, 34.0), "LocationState should round-trip")


func _test_map_scene_content() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	var story := load("res://stories/lab/borrowed_umbrella.tres") as StoryModule
	_expect(
		story.get_objective_text(&"looking_for_owner", &"map.lab.inn_hall")
		== "去雨院寻找蓑衣客",
		"story module should own its objective text"
	)
	var errors := database.build_index()
	errors.append_array(MapSceneValidator.new().validate(database, story))
	_expect(errors.is_empty(), "map scene content should validate: %s" % "; ".join(errors))
	for map_id: StringName in [&"map.lab.inn_hall", &"map.lab.rain_courtyard"]:
		var definition := database.map(map_id)
		var map_scene := definition.scene.instantiate() as MapGameScene
		_expect(map_scene != null, "map scene should inherit the shared MapGameScene base: %s" % map_id)
		if map_scene != null:
			var ground := map_scene.get_node(^"GroundLayer") as TileMapLayer
			var details := map_scene.get_node(^"DetailLayer") as TileMapLayer
			_expect(ground.get_used_cells().size() == 150, "map should store 150 ground cells: %s" % map_id)
			_expect(details.get_used_cells().size() == 23, "map should store 23 detail cells: %s" % map_id)
			map_scene.free()
	_test_map_scene_validation_failures(database, story)


func _test_map_scene_validation_failures(
	database: ContentDatabase,
	story: StoryModule
) -> void:
	var source_hall := database.map(&"map.lab.inn_hall")
	var invalid_hall_scene := source_hall.scene.instantiate() as MapGameScene
	(invalid_hall_scene.get_node(^"GroundLayer") as TileMapLayer).clear()
	invalid_hall_scene.entry_trigger_id = &"missing_trigger"
	var innkeeper := invalid_hall_scene.get_node(^"YSortRoot/Innkeeper/Interactable") as Interactable
	var guest := invalid_hall_scene.get_node(^"YSortRoot/QuietGuest/Interactable") as Interactable
	guest.persistent_id = innkeeper.persistent_id
	var portal := invalid_hall_scene.get_node(^"YSortRoot/CourtyardDoor/Interactable") as Interactable
	portal.portal_target_spawn_id = &"missing_spawn"
	var invalid_packed_scene := PackedScene.new()
	var pack_error := invalid_packed_scene.pack(invalid_hall_scene)
	invalid_hall_scene.free()
	_expect(pack_error == OK, "invalid map fixture should pack in memory")
	if pack_error != OK:
		return
	var hall_definition := _copy_map_definition(source_hall)
	hall_definition.scene = invalid_packed_scene
	var courtyard_definition := _copy_map_definition(database.map(&"map.lab.rain_courtyard"))
	var invalid_database := ContentDatabase.new()
	invalid_database.maps.assign([hall_definition, courtyard_definition])
	var errors := invalid_database.build_index()
	errors.append_array(MapSceneValidator.new().validate(invalid_database, story))
	_expect(_has_error(errors, "GroundLayer has no painted cells"), "validator should reject an empty TileMapLayer")
	_expect(_has_error(errors, "missing_trigger"), "validator should reject an unknown entry trigger")
	_expect(_has_error(errors, "repeated persistent ID"), "validator should reject repeated persistent IDs")
	_expect(_has_error(errors, "missing_spawn"), "validator should reject an unknown portal spawn")


func _copy_map_definition(source: MapDefinition) -> MapDefinition:
	var result := MapDefinition.new()
	result.id = source.id
	result.display_name = source.display_name
	result.description = source.description
	result.tags = source.tags.duplicate()
	result.scene = source.scene
	result.default_spawn_id = source.default_spawn_id
	result.music_source_id = source.music_source_id
	return result


func _has_error(errors: PackedStringArray, fragment: String) -> bool:
	for error: String in errors:
		if fragment in error:
			return true
	return false


func _test_scene_smoke() -> void:
	var root_scene := load("res://scenes/root/game_root.tscn") as PackedScene
	var game_root := root_scene.instantiate() as GameRoot
	get_root().add_child(game_root)
	await process_frame
	_expect(game_root.scene_stack.current_scene() is TitleGameScene, "title scene should be first")
	game_root.start_new_game()
	await _drain_dialogue(game_root)
	var hall := game_root.scene_stack.current_scene() as MapGameScene
	_expect(hall != null and hall.map_id == &"map.lab.inn_hall", "new game should load the hall")
	if hall != null:
		_expect(hall.ground_layer.get_used_cells().size() == 150, "hall should load its stored TileMapLayer")
		_expect(hall.player.control_enabled, "player input should unlock after entry dialogue")
		hall.player.position = (hall.get_node("YSortRoot/Innkeeper") as Node2D).position
		hall._on_player_interact()
		await _drain_dialogue(game_root)
		_expect(
			game_root.game_run.story.get_stage(&"story.lab.borrowed_umbrella", &"")
			== &"looking_for_owner",
			"the real innkeeper binding should start the story"
		)
	var courtyard_definition := game_root.content_database.map(&"map.lab.rain_courtyard")
	game_root.travel_to(courtyard_definition, &"from_hall")
	await _drain_dialogue(game_root)
	var courtyard := game_root.scene_stack.current_scene() as MapGameScene
	_expect(
		courtyard != null and courtyard.map_id == &"map.lab.rain_courtyard",
		"travel should replace the active map"
	)
	if courtyard != null:
		_expect(courtyard.ground_layer.get_used_cells().size() == 150, "courtyard should load its stored TileMapLayer")
		courtyard.player.position = (courtyard.get_node("YSortRoot/Traveler") as Node2D).position
		courtyard._on_player_interact()
		await _drain_dialogue(game_root)
		_expect(
			game_root.game_run.story.get_stage(&"story.lab.borrowed_umbrella", &"")
			== &"owner_found",
			"the real traveler binding should identify the umbrella"
		)
		var umbrella := courtyard.get_node("YSortRoot/Umbrella") as Node2D
		courtyard.player.position = umbrella.position
		courtyard._on_player_interact()
		await _drain_dialogue(game_root)
		_expect(not umbrella.visible, "completed source entity should hide the umbrella immediately")
		_expect(
			game_root.game_run.world.is_completed(&"map.lab.rain_courtyard", &"old_umbrella"),
			"completed source entity should persist in WorldState"
		)
	var hall_definition := game_root.content_database.map(&"map.lab.inn_hall")
	game_root.travel_to(hall_definition, &"from_courtyard")
	await _drain_dialogue(game_root)
	hall = game_root.scene_stack.current_scene() as MapGameScene
	if hall != null:
		hall.player.position = (hall.get_node("YSortRoot/Innkeeper") as Node2D).position
		hall._on_player_interact()
		await _drain_dialogue(game_root)
	_expect(
		game_root.game_run.story.get_stage(&"story.lab.borrowed_umbrella", &"") == &"completed",
		"the real two-map story should reach its completed stage"
	)
	var save_error := game_root.save_service.save_run(game_root.game_run, TEST_SAVE)
	_expect(save_error == OK, "SaveService should write an atomic test save")
	var loaded := game_root.save_service.load_run(TEST_SAVE)
	_expect(loaded != null, "SaveService should load the test save")
	if loaded != null:
		_expect(
			loaded.story.get_stage(&"story.lab.borrowed_umbrella", &"") == &"completed",
			"SaveService should preserve story progress"
		)
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	game_root.queue_free()
	await process_frame


func _drain_dialogue(game_root: GameRoot) -> void:
	await process_frame
	await process_frame
	for _frame: int in range(30):
		await process_frame
		if game_root.dialogue_layer.is_active():
			await process_frame
			game_root.dialogue_layer.advance_requested.emit()
		if not game_root.story_director.is_busy() and not game_root.dialogue_layer.is_active():
			return
	_expect(false, "dialogue/story call did not settle within 30 frames")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
