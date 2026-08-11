extends SceneTree

const OUTPUT_DIRECTORY := "/tmp/godot-pal-framework-lab"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIRECTORY)
	var root_scene := load("res://scenes/root/game_root.tscn") as PackedScene
	var game_root := root_scene.instantiate() as GameRoot
	get_root().add_child(game_root)
	await process_frame
	game_root.start_new_game()
	await _wait_for_dialogue(game_root)
	if await _save_viewport("hall_dialogue.png") != OK:
		_finish_with_error(game_root)
		return
	await _drain_dialogue(game_root)
	if await _save_viewport("hall.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.game_run.story.set_stage(&"story.lab.borrowed_umbrella", &"looking_for_owner")
	var courtyard := game_root.content_database.map(&"map.lab.rain_courtyard")
	game_root.travel_to(courtyard, &"from_hall")
	await _drain_dialogue(game_root)
	if await _save_viewport("courtyard.png") != OK:
		_finish_with_error(game_root)
		return
	print("captured framework-lab scenes in %s" % OUTPUT_DIRECTORY)
	game_root.free()
	quit()


func _wait_for_dialogue(game_root: GameRoot) -> void:
	for _frame: int in range(20):
		await process_frame
		if game_root.dialogue_layer.is_active():
			return


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


func _save_viewport(file_name: String) -> Error:
	await process_frame
	await process_frame
	var viewport_texture := get_root().get_texture()
	if viewport_texture == null:
		push_error("viewport capture is unavailable; run this script with a display renderer")
		return ERR_UNAVAILABLE
	var image := viewport_texture.get_image()
	if image == null:
		push_error("viewport capture is unavailable; run this script with a display renderer")
		return ERR_UNAVAILABLE
	var error := image.save_png(OUTPUT_DIRECTORY.path_join(file_name))
	if error != OK:
		push_error("failed to save %s: %s" % [file_name, error_string(error)])
	return error


func _finish_with_error(game_root: GameRoot) -> void:
	game_root.free()
	quit(1)
