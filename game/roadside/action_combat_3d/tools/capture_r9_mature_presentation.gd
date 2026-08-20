extends SceneTree

const OUTPUT_DIR := "/tmp/godot-pal-r9"
const SAVE_DIR := "/tmp/godot-pal-r9-saves"
const GAME_ROOT_SCENE := preload("res://game/bootstrap/game_root.tscn")

var _game_root: GameRoot


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_clear_pngs(OUTPUT_DIR)
	_clear_directory(SAVE_DIR)
	_game_root = GAME_ROOT_SCENE.instantiate() as GameRoot
	get_root().add_child(_game_root)
	await _wait_frames(3)
	if await _capture("01_title_first_focus") != OK:
		_finish(1)
		return

	_game_root.start_new_game()
	await _wait_frames(5)
	var scene := _game_root.scene_stack.current_scene() as MapGameScene3D
	if scene == null or scene.map_id != &"map.roadside.lantern_pass":
		push_error("R9 capture expected new game to enter the lantern pass")
		_finish(1)
		return
	_freeze_map(scene)
	_focus_player(scene, Vector3(0.0, 0.05, 38.0))
	if await _capture("02_lantern_entry") != OK:
		_finish(1)
		return

	var ground_target := scene.player_3d.global_position + Vector3(2.4, 0.0, -1.2)
	scene.map_hud.show_ground_click(scene.camera_3d.unproject_position(ground_target))
	if await _capture("03_ground_click") != OK:
		_finish(1)
		return

	var keeper := scene.get_node(^"WorldRoot/LanternKeeper") as Node3D
	_focus_player(scene, keeper.global_position + Vector3(1.15, 0.0, 0.0))
	scene._refresh_interaction_prompt()
	if await _capture("04_keeper_interaction") != OK:
		_finish(1)
		return

	var first_source := _source(scene, ^"WorldRoot/EncounterSources/FirstPack")
	var first_session := _begin_direct_encounter(scene, first_source)
	_focus_player(scene, Vector3(0.0, 0.05, 32.0))
	var target_enemy := first_source.enemy_views[0]
	scene.set("_pointer_enemy", target_enemy)
	scene.pointer_feedback.set_target(target_enemy)
	scene._refresh_battle_hud()
	if await _capture("05_keyboard_battle") != OK:
		_finish(1)
		return

	var gamepad_event := InputEventJoypadButton.new()
	gamepad_event.button_index = JOY_BUTTON_START
	gamepad_event.pressed = true
	scene._input(gamepad_event)
	scene._refresh_battle_hud()
	if await _capture("06_gamepad_battle") != OK:
		_finish(1)
		return

	target_enemy._start_attack_telegraph(BattleSession.BASIC_ATTACK_ID)
	var attack_direction := target_enemy.global_position - scene.player_3d.global_position
	scene.combat_feedback.show_slash(
		scene.player_3d.global_position + Vector3(0.0, 0.9, 0.0),
		attack_direction
	)
	scene.combat_feedback.show_hit_spark(
		target_enemy.global_position + Vector3(0.0, 0.65, 0.0)
	)
	if await _capture("07_windup_and_hit") != OK:
		_finish(1)
		return
	target_enemy._finish_attack_telegraph()
	scene.escape_battle()
	scene.result_label.visible = false

	var boss_source := _source(scene, ^"WorldRoot/EncounterSources/StoneBeast")
	var boss_session := _begin_direct_encounter(scene, boss_source)
	_focus_player(scene, Vector3(0.0, 0.05, -17.0))
	var boss_actor := boss_session.enemies[0]
	var charge := scene.request_battle_action(
		BattleActionIntent.charge(boss_actor.id, boss_session.player.id)
	)
	if not charge.accepted():
		push_error("R9 capture could not start the Boss charge")
		_finish(1)
		return
	scene._refresh_battle_hud()
	if await _capture("08_boss_charge") != OK:
		_finish(1)
		return
	scene.escape_battle()
	scene.result_label.visible = false

	var story := scene.story_module as LanternPassStory
	_open_dialogue(story.dialogue, &"gear_choice")
	await _advance_to_option()
	if await _capture("09_dialogue_choice") != OK:
		_finish(1)
		return
	_game_root.dialogue_layer.option_selected.emit(&"sword_seal")
	await _wait_dialogue_closed()

	_game_root.scene_stack.push(_game_root.menu_scene)
	await _wait_frames(2)
	if await _capture("10_pause_menu") != OK:
		_finish(1)
		return

	_game_root.scene_stack.push(_game_root.settings_scene)
	await _wait_frames(2)
	var settings := _game_root.scene_stack.current_scene() as SettingsGameScene
	settings._show_category(SettingsGameScene.SettingsCategory.CONTROLS)
	settings.action_list.select(SettingsService.REBINDABLE_ACTIONS.find(&"combat_attack"))
	settings._begin_rebind()
	if await _capture("11_settings_rebind") != OK:
		_finish(1)
		return
	_game_root.scene_stack.pop()
	await _wait_frames(2)

	_game_root.save_service.configure_slots_directory(SAVE_DIR)
	_game_root.game_run.economy.money = 36
	if _game_root.save_service.save_slot(_game_root.game_run, 1) != OK:
		push_error("R9 capture could not create its temporary save summary")
		_finish(1)
		return
	_game_root.scene_stack.push(_game_root.save_load_scene, {"save": false})
	await _wait_frames(2)
	if await _capture("12_save_load_summary") != OK:
		_finish(1)
		return

	print("R9 mature-presentation screenshots written to %s" % OUTPUT_DIR)
	_finish(0)


func _source(scene: MapGameScene3D, path: NodePath) -> EncounterSource3D:
	return scene.get_node_or_null(path) as EncounterSource3D


func _begin_direct_encounter(
	scene: MapGameScene3D,
	source: EncounterSource3D
) -> BattleSession:
	scene.set("_active_source", source)
	source.triggering = true
	return scene.begin_battle(source.encounter)


func _freeze_map(scene: MapGameScene3D) -> void:
	scene.set_process(false)
	scene.player_3d.set_physics_process(false)
	for enemy_view: EnemyActorView3D in scene.enemy_views():
		enemy_view.set_physics_process(false)


func _focus_player(scene: MapGameScene3D, position: Vector3) -> void:
	scene.player_3d.global_position = position
	scene._update_camera(0.0)


func _open_dialogue(dialogue: DialogueDefinition, block_id: StringName) -> void:
	await _game_root.dialogue_layer.show_dialogue(dialogue, block_id)


func _advance_to_option() -> void:
	for _frame: int in range(600):
		if _game_root.dialogue_layer.is_waiting_for_option():
			return
		if _game_root.dialogue_layer.is_active():
			_game_root.dialogue_layer.advance_requested.emit()
		await process_frame
	push_error("R9 capture timed out waiting for a dialogue option")


func _wait_dialogue_closed() -> void:
	for _frame: int in range(240):
		if not _game_root.dialogue_layer.is_active():
			return
		await process_frame
	push_error("R9 capture timed out closing dialogue")


func _capture(name: String) -> Error:
	await process_frame
	if _game_root.dialogue_layer.is_active():
		_game_root.dialogue_layer.complete_typing()
	await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	if image == null or image.get_size() != Vector2i(640, 360):
		push_error("unexpected R9 capture image")
		return ERR_INVALID_DATA
	return image.save_png(OUTPUT_DIR.path_join("%s.png" % name))


func _clear_pngs(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		if file_name.get_extension().to_lower() == "png":
			directory.remove(file_name)


func _clear_directory(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _finish(exit_code: int) -> void:
	if _game_root != null:
		var current_map := _game_root.scene_stack.current_scene() as MapGameScene3D
		if current_map != null:
			current_map._clear_custom_cursors()
		_game_root.queue_free()
	_clear_directory(SAVE_DIR)
	_quit_after_cleanup(exit_code)


func _quit_after_cleanup(exit_code: int) -> void:
	await _wait_frames(2)
	quit(exit_code)
