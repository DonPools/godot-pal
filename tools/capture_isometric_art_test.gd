extends SceneTree

const OUTPUT_DIRECTORY := "/tmp/godot-pal-roadside"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIRECTORY)
	var packed := load("res://scenes/root/game_root.tscn") as PackedScene
	var game_root := packed.instantiate() as GameRoot
	get_root().add_child(game_root)
	await process_frame
	if await _save_viewport("title.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.start_new_game()
	await process_frame
	await process_frame
	var scene := game_root.scene_stack.current_scene() as MapGameScene
	scene.player.set_direction(&"east")
	scene.player.position = Vector2(-32, 104)
	if await _save_viewport("roadside.png") != OK:
		_finish_with_error(game_root)
		return
	scene.player.set_direction(&"north")
	scene.player.position = Vector2(0, 56)
	if await _save_viewport("tree_behind.png") != OK:
		_finish_with_error(game_root)
		return
	scene.player.set_direction(&"south")
	scene.player.position = Vector2(0, 104)
	if await _save_viewport("tree_front.png") != OK:
		_finish_with_error(game_root)
		return
	scene.player.set_direction(&"east")
	scene.player.position = Vector2(20, 112)
	scene._on_player_interact()
	await process_frame
	if await _save_viewport("dialogue.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.dialogue_layer.advance_requested.emit()
	await process_frame
	game_root.dialogue_layer.advance_requested.emit()
	await process_frame
	if await _save_viewport("commission_choice.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.dialogue_layer.option_selected.emit(&"accept")
	await process_frame
	game_root.dialogue_layer.advance_requested.emit()
	await process_frame
	if await _save_viewport("route_choice.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.dialogue_layer.option_selected.emit(&"safe_route")
	await process_frame
	await _finish_story_dialogues(game_root)
	await process_frame
	await process_frame
	var slope := game_root.scene_stack.current_scene() as MapGameScene
	await _finish_story_dialogues(game_root)
	slope.player.set_direction(&"east")
	slope.player.position = Vector2(-92, 72)
	if await _save_viewport("herb_slope.png") != OK:
		_finish_with_error(game_root)
		return
	var patch := slope.get_node(^"YSortRoot/HerbWest") as HarvestPatch
	slope.player.position = patch.position + Vector2(-16, 0)
	slope._on_player_interact()
	await process_frame
	game_root.dialogue_layer.advance_requested.emit()
	await process_frame
	if await _save_viewport("harvest_choice.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.dialogue_layer.option_selected.emit(&"leave_root")
	await process_frame
	await _finish_story_dialogues(game_root)
	slope.player.position = patch.position + Vector2(-36, 16)
	if await _save_viewport("herb_left_root.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.game_run.flags.set_value(RoadsideGatheringStory.SECOND_TRIP_STARTED)
	game_root.game_run.story.set_stage(&"story.roadside.gathering", &"trip_two_early")
	patch.refresh()
	slope.player.position = patch.position + Vector2(-36, 16)
	if await _save_viewport("herb_regrown.png") != OK:
		_finish_with_error(game_root)
		return
	slope.player.position = patch.position + Vector2(-16, 0)
	slope._on_player_interact()
	await process_frame
	game_root.dialogue_layer.advance_requested.emit()
	await process_frame
	game_root.dialogue_layer.option_selected.emit(&"uproot")
	await process_frame
	await _finish_story_dialogues(game_root)
	slope.player.position = patch.position + Vector2(-36, 16)
	if await _save_viewport("herb_uprooted.png") != OK:
		_finish_with_error(game_root)
		return
	print("captured formal roadside gathering slice in %s" % OUTPUT_DIRECTORY)
	game_root.queue_free()
	await process_frame
	quit()


func _save_viewport(file_name: String) -> Error:
	_freeze_animated_sprites(get_root())
	await process_frame
	await process_frame
	var image := get_root().get_texture().get_image()
	if image == null:
		push_error("viewport capture is unavailable; run with a display renderer")
		return ERR_UNAVAILABLE
	if image.get_size() != Vector2i(320, 180):
		push_error("unexpected capture size: %s" % image.get_size())
		return ERR_INVALID_DATA
	return image.save_png(OUTPUT_DIRECTORY.path_join(file_name))


func _freeze_animated_sprites(node: Node) -> void:
	if node is AnimatedSprite2D:
		var sprite := node as AnimatedSprite2D
		sprite.pause()
		sprite.frame = 0
		sprite.frame_progress = 0.0
	for child: Node in node.get_children():
		_freeze_animated_sprites(child)


func _finish_story_dialogues(game_root: GameRoot) -> void:
	while game_root.story_director.is_busy():
		if game_root.dialogue_layer.is_waiting_for_option():
			push_error("capture encountered an unexpected dialogue option")
			return
		if game_root.dialogue_layer.is_active():
			game_root.dialogue_layer.advance_requested.emit()
		await process_frame


func _finish_with_error(scene: Node) -> void:
	scene.free()
	quit(1)
