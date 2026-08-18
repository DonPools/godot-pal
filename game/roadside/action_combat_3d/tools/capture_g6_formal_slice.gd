extends SceneTree

const OUTPUT_DIR := "/tmp/godot-pal-g6"
const GAME_ROOT_SCENE := preload("res://game/bootstrap/game_root.tscn")

var _game_root: GameRoot


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_game_root = GAME_ROOT_SCENE.instantiate() as GameRoot
	get_root().add_child(_game_root)
	await process_frame
	if await _capture("01_title") != OK:
		_finish(1)
		return

	_game_root.start_new_game()
	await _wait_frames(4)
	var scene := _current_map()
	_freeze_map(scene)
	if await _capture("02_north_slope_wilds") != OK:
		_finish(1)
		return

	var shop := _game_root.content_database.map(&"map.roadside.shop")
	_game_root.travel_to(shop, shop.default_spawn_id)
	await _wait_frames(4)
	scene = _current_map()
	_freeze_map(scene)
	var shopkeeper := scene.get_node(^"WorldRoot/Shopkeeper") as NpcCharacter3D
	_focus_player(scene, shopkeeper.global_position + Vector3(-1.6, 0.0, 0.8))
	if await _capture("03_roadside_shop") != OK:
		_finish(1)
		return

	_interact(scene, ^"WorldRoot/Shopkeeper/Interactable")
	await _wait_for_dialogue()
	if await _capture("04_shopkeeper_dialogue") != OK:
		_finish(1)
		return
	await _advance_to_option()
	if await _capture("05_commission_choice") != OK:
		_finish(1)
		return
	_game_root.dialogue_layer.option_selected.emit(&"accept")
	await _advance_to_option()
	if await _capture("06_route_choice") != OK:
		_finish(1)
		return
	_game_root.dialogue_layer.option_selected.emit(&"safe_route")
	await _finish_story_dialogues()
	await _wait_frames(4)

	scene = _current_map()
	await _finish_story_dialogues()
	_freeze_map(scene)
	var patch := scene.get_node(^"WorldRoot/HerbWest") as HarvestPatch3D
	_focus_player(scene, patch.global_position + Vector3(-1.5, 0.0, 0.8))
	if await _capture("07_herb_slope_full") != OK:
		_finish(1)
		return

	_interact(scene, ^"WorldRoot/HerbWest/Interactable")
	await _advance_to_option()
	if await _capture("08_harvest_choice") != OK:
		_finish(1)
		return
	_game_root.dialogue_layer.option_selected.emit(&"leave_root")
	await _finish_story_dialogues()
	if await _capture("09_herb_cut") != OK:
		_finish(1)
		return

	_game_root.game_run.flags.set_value(RoadsideGatheringStory.SECOND_TRIP_STARTED)
	_game_root.game_run.story.set_stage(&"story.roadside.gathering", &"trip_two_early")
	patch.refresh_world_state()
	if await _capture("10_herb_regrown") != OK:
		_finish(1)
		return

	_interact(scene, ^"WorldRoot/HerbWest/Interactable")
	await _advance_to_option()
	_game_root.dialogue_layer.option_selected.emit(&"uproot")
	await _finish_story_dialogues()
	if await _capture("11_herb_uprooted") != OK:
		_finish(1)
		return

	print("G6 formal screenshots written to %s" % OUTPUT_DIR)
	_finish(0)


func _current_map() -> MapGameScene3D:
	return _game_root.scene_stack.current_scene() as MapGameScene3D


func _freeze_map(scene: MapGameScene3D) -> void:
	if scene == null:
		return
	scene.set_process(false)
	if scene.player_3d != null:
		scene.player_3d.set_physics_process(false)
	for enemy_view: EnemyActorView3D in scene.enemy_views():
		enemy_view.set_physics_process(false)


func _focus_player(scene: MapGameScene3D, position: Vector3) -> void:
	scene.player_3d.global_position = position
	scene._update_camera(0.0)


func _interact(scene: MapGameScene3D, path: NodePath) -> void:
	var interactable := scene.get_node_or_null(path) as StoryInteractable3D
	if interactable == null:
		push_error("capture interaction target is missing: %s" % path)
		return
	scene.player_3d.global_position = interactable.global_position + Vector3(1.2, 0.0, 0.0)
	scene._on_player_interact_3d()


func _wait_for_dialogue() -> void:
	for _frame: int in range(240):
		if _game_root.dialogue_layer.is_active():
			return
		await process_frame
	push_error("capture timed out waiting for dialogue")


func _advance_to_option() -> void:
	for _frame: int in range(600):
		if _game_root.dialogue_layer.is_waiting_for_option():
			return
		if _game_root.dialogue_layer.is_active():
			_game_root.dialogue_layer.advance_requested.emit()
		await process_frame
	push_error("capture timed out waiting for a dialogue option")


func _finish_story_dialogues() -> void:
	var idle_frames := 0
	for _frame: int in range(1200):
		if _game_root.story_director.is_busy() or _game_root.dialogue_layer.is_active():
			idle_frames = 0
			if _game_root.dialogue_layer.is_waiting_for_option():
				push_error("capture encountered an unexpected dialogue option")
				return
			if _game_root.dialogue_layer.is_active():
				_game_root.dialogue_layer.advance_requested.emit()
		else:
			idle_frames += 1
			if idle_frames >= 3:
				return
		await process_frame
	push_error("capture timed out finishing story dialogue")


func _capture(name: String) -> Error:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	if image == null or image.get_size() != Vector2i(640, 360):
		push_error("unexpected capture image: %s" % [image.get_size() if image != null else null])
		return ERR_INVALID_DATA
	return image.save_png(OUTPUT_DIR.path_join("%s.png" % name))


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _finish(exit_code: int) -> void:
	_game_root.free()
	quit(exit_code)
