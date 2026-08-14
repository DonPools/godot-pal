extends SceneTree

const OUTPUT_DIRECTORY := "/tmp/godot-pal-framework-lab"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIRECTORY)
	var root_scene := load("res://game/bootstrap/game_root.tscn") as PackedScene
	var game_root := root_scene.instantiate() as GameRoot
	get_root().add_child(game_root)
	await process_frame
	_configure_deterministic_settings(game_root)
	if await _save_viewport("title.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.start_new_game()
	if not await _wait_for_dialogue(game_root):
		push_error("opening dialogue did not become active within the capture deadline")
		_finish_with_error(game_root)
		return
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
	var herbal_room := game_root.content_database.map(&"map.lab.herbal_room")
	game_root.travel_to(herbal_room, &"from_hall")
	await process_frame
	await process_frame
	if await _save_viewport("herbal_room.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.game_run.inventory.add_item(
		game_root.content_database.item(&"item.lab.healing_herb"),
		2
	)
	game_root.game_run.inventory.add_item(
		game_root.content_database.item(&"item.lab.spirit_draught")
	)
	game_root.scene_stack.push(game_root.menu_scene)
	await process_frame
	if await _save_viewport("menu.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.scene_stack.push(game_root.save_load_scene, {"save": true})
	await process_frame
	if await _save_viewport("save_slots.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.scene_stack.pop()
	game_root.scene_stack.push(game_root.settings_scene)
	await process_frame
	if await _save_viewport("settings.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.scene_stack.pop()
	game_root.scene_stack.pop()
	var shop_scene := load("res://game/presentation/shop/shop_game_scene.tscn") as PackedScene
	game_root.scene_stack.push(shop_scene, game_root.content_database.shop(&"shop.lab.herbal_room"))
	await process_frame
	if await _save_viewport("shop.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.scene_stack.pop()
	var bridge := game_root.content_database.map(&"map.lab.broken_bridge")
	game_root.travel_to(bridge, &"from_courtyard")
	await process_frame
	await process_frame
	if await _save_viewport("broken_bridge.png") != OK:
		_finish_with_error(game_root)
		return
	var current_bridge := game_root.scene_stack.current_scene() as MapGameScene
	current_bridge.player.position = (
		current_bridge.get_node("YSortRoot/Bandit") as Node2D
	).position
	current_bridge._on_player_interact()
	await process_frame
	if await _save_viewport("battle.png") != OK:
		_finish_with_error(game_root)
		return
	game_root.scene_stack.pop(BattleResult.new())
	for _frame: int in range(10):
		await process_frame
		if not game_root.story_director.is_busy():
			break
	print("captured framework-lab scenes in %s" % OUTPUT_DIRECTORY)
	game_root.queue_free()
	await process_frame
	await process_frame
	quit()


func _wait_for_dialogue(game_root: GameRoot) -> bool:
	for _frame: int in range(90):
		await process_frame
		if game_root.dialogue_layer.is_active():
			return true
	return false


func _configure_deterministic_settings(game_root: GameRoot) -> void:
	game_root.settings_service.set_locale(&"zh_CN", false)
	game_root.settings_service.set_music_enabled(true, false)
	game_root.settings_service.set_sound_enabled(true, false)
	var bindings := {
		&"move_north": KEY_UP,
		&"move_south": KEY_DOWN,
		&"move_west": KEY_LEFT,
		&"move_east": KEY_RIGHT,
		&"interact": KEY_ENTER,
		&"menu": KEY_M,
	}
	for action: StringName in bindings:
		game_root.settings_service.set_key_binding(action, bindings[action], false)
	var title := game_root.scene_stack.current_scene() as TitleGameScene
	if title != null:
		title._refresh_text()


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
	_freeze_animated_sprites(get_root())
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


func _freeze_animated_sprites(node: Node) -> void:
	if node is AnimatedSprite2D:
		var sprite := node as AnimatedSprite2D
		sprite.pause()
		sprite.frame = 0
		sprite.frame_progress = 0.0
	for child: Node in node.get_children():
		_freeze_animated_sprites(child)


func _finish_with_error(game_root: GameRoot) -> void:
	game_root.free()
	quit(1)
