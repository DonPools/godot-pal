extends SceneTree

const OUTPUT_DIRECTORY := "res://tests/fixtures/save_baselines"
const NEW_GAME_PATH := OUTPUT_DIRECTORY + "/new_game_v3.json"
const GATHERING_COMPLETED_PATH := OUTPUT_DIRECTORY + "/gathering_completed_v3.json"


func _initialize() -> void:
	call_deferred("_generate")


func _generate() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	if database == null:
		_finish_with_error("save baseline generator could not load ContentDatabase")
		return
	var content_errors := database.build_index()
	if not content_errors.is_empty():
		_finish_with_error("save baseline content is invalid: %s" % content_errors[0])
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	)
	if directory_error != OK:
		_finish_with_error("save baseline directory could not be created")
		return
	var save_service := SaveService.new()
	get_root().add_child(save_service)
	save_service.configure(database)
	var new_game := _new_game_baseline(database)
	var completed := _completed_gathering_baseline(database)
	if save_service.save_run(new_game, NEW_GAME_PATH) != OK:
		_finish_with_error("new game baseline could not be saved", save_service)
		return
	if save_service.save_run(completed, GATHERING_COMPLETED_PATH) != OK:
		_finish_with_error("completed gathering baseline could not be saved", save_service)
		return
	var restored_new_game := save_service.load_run(NEW_GAME_PATH)
	var restored_completed := save_service.load_run(GATHERING_COMPLETED_PATH)
	if restored_new_game == null or restored_completed == null:
		_finish_with_error("generated save baseline did not round-trip", save_service)
		return
	if (
		restored_completed.story.get_stage(&"story.roadside.gathering", &"not_started")
		!= &"completed"
		or not restored_completed.world.is_completed(
			&"map.roadside.herb_slope",
			&"herb_patch.centre"
		)
	):
		_finish_with_error("completed gathering baseline lost persistent progress", save_service)
		return
	print(JSON.stringify({
		"command": "generate-2d-save-baselines",
		"ok": true,
		"files": [NEW_GAME_PATH, GATHERING_COMPLETED_PATH],
	}))
	save_service.queue_free()
	await process_frame
	quit()


func _new_game_baseline(database: ContentDatabase) -> GameRun:
	var run := GameRun.new_game(database, 260818)
	run.location.map_id = &"map.roadside.north_slope_wilds"
	run.location.spawn_id = &"default"
	run.location.has_exact_position = false
	return run


func _completed_gathering_baseline(database: ContentDatabase) -> GameRun:
	var run := GameRun.new_game(database, 260819)
	run.location.map_id = &"map.roadside.shop"
	run.location.spawn_id = &"from_slope"
	run.location.has_exact_position = false
	run.economy.money += 18
	run.story.set_stage(&"story.roadside.gathering", &"completed")
	for flag_id: StringName in [
		RoadsideGatheringStory.ENTERED_TRIP_ONE,
		RoadsideGatheringStory.FIRST_WEST,
		RoadsideGatheringStory.FIRST_CENTRE,
		RoadsideGatheringStory.SECOND_TRIP_STARTED,
		RoadsideGatheringStory.ENTERED_TRIP_TWO,
		RoadsideGatheringStory.SECOND_WEST,
		RoadsideGatheringStory.SECOND_CENTRE,
		RoadsideGatheringStory.UPROOTED_CENTRE,
	]:
		run.flags.set_value(flag_id)
	run.world.complete(&"map.roadside.herb_slope", &"herb_patch.centre")
	return run


func _finish_with_error(message: String, scene: Node = null) -> void:
	push_error(message)
	if scene != null:
		scene.queue_free()
	quit(1)
