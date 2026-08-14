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
	print("captured formal roadside slice in %s" % OUTPUT_DIRECTORY)
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


func _finish_with_error(scene: Node) -> void:
	scene.free()
	quit(1)
