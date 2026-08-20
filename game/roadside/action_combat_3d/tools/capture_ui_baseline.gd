extends SceneTree

const OUTPUT_DIR := "/tmp/godot-pal-ui"
const GAME_ROOT_SCENE := preload("res://game/bootstrap/game_root.tscn")

var _game_root: GameRoot


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_clear_previous_captures()
	_game_root = GAME_ROOT_SCENE.instantiate() as GameRoot
	get_root().add_child(_game_root)
	await process_frame
	_game_root.start_new_game()
	await _wait_frames(4)
	var scene := _game_root.scene_stack.current_scene() as MapGameScene3D
	if scene == null or scene.map_id != &"map.roadside.lantern_pass":
		push_error("UI capture expected the lantern pass")
		_finish(1)
		return
	_freeze_map(scene)
	scene._update_camera(0.0)
	var ground_target := scene.player_3d.global_position + Vector3(2.4, 0.0, -0.8)
	var ground_screen_position := scene.camera_3d.unproject_position(ground_target)
	var ground_click := InputEventMouseButton.new()
	ground_click.button_index = MOUSE_BUTTON_LEFT
	ground_click.position = ground_screen_position
	ground_click.pressed = true
	scene._unhandled_input(ground_click)
	if await _capture("01_ground_click_navigation") != OK:
		_finish(1)
		return
	ground_click.pressed = false
	scene._unhandled_input(ground_click)

	var keeper := scene.get_node(^"WorldRoot/LanternKeeper") as Node3D
	scene.player_3d.global_position = keeper.global_position + Vector3(1.15, 0.0, 0.0)
	scene._update_camera(0.0)
	scene._refresh_interaction_prompt()
	if await _capture("02_interaction_prompt") != OK:
		_finish(1)
		return

	var source := scene.get_node(
		^"WorldRoot/EncounterSources/FirstPack"
	) as EncounterSource3D
	scene.set("_active_source", source)
	source.triggering = true
	var session := scene.begin_battle(source.encounter)
	scene.player_3d.global_position = Vector3(0.0, 0.05, 32.0)
	scene._update_camera(0.0)
	var target_enemy := source.enemy_views[0]
	scene.set("_pointer_enemy", target_enemy)
	scene.pointer_feedback.set_target(target_enemy)
	scene._refresh_battle_hud()
	if await _capture("03_keyboard_battle_hud") != OK:
		_finish(1)
		return

	var gamepad_event := InputEventJoypadButton.new()
	gamepad_event.button_index = JOY_BUTTON_START
	gamepad_event.pressed = true
	scene._input(gamepad_event)
	scene._refresh_battle_hud()
	if await _capture("04_gamepad_battle_hud") != OK:
		_finish(1)
		return

	session.player.mp = 0
	var leader := _game_root.game_run.party.leader()
	var skill := _game_root.content_database.skill(leader.skill_ids[0])
	scene.request_battle_action(
		BattleActionIntent.use_skill(session.player.id, skill)
	)
	scene._refresh_battle_hud()
	if await _capture("05_resource_feedback") != OK:
		_finish(1)
		return

	_game_root.scene_stack.push(_game_root.settings_scene)
	await _wait_frames(2)
	if await _capture("06_settings_input_accessibility") != OK:
		_finish(1)
		return

	print("UI screenshots written to %s" % OUTPUT_DIR)
	_finish(0)


func _clear_previous_captures() -> void:
	var directory := DirAccess.open(OUTPUT_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		if file_name.get_extension().to_lower() == "png":
			directory.remove(file_name)


func _freeze_map(scene: MapGameScene3D) -> void:
	scene.set_process(false)
	scene.player_3d.set_physics_process(false)
	for enemy_view: EnemyActorView3D in scene.enemy_views():
		enemy_view.set_physics_process(false)


func _capture(name: String) -> Error:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	if image == null or image.get_size() != Vector2i(640, 360):
		push_error("unexpected UI capture image")
		return ERR_INVALID_DATA
	return image.save_png(OUTPUT_DIR.path_join("%s.png" % name))


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _finish(exit_code: int) -> void:
	_game_root.free()
	quit(exit_code)
