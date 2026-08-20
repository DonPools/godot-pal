extends SceneTree

const GAME_ROOT_SCENE := preload("res://game/bootstrap/game_root.tscn")
const TEMP_SAVE_DIR := "/tmp/godot-pal-r9-dynamic-saves"

var _game_root: GameRoot
var _mode := "golden"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_mode = arguments[0]
	call_deferred("_run")


func _run() -> void:
	_game_root = GAME_ROOT_SCENE.instantiate() as GameRoot
	get_root().add_child(_game_root)
	await _wait_frames(45)
	match _mode:
		"golden":
			await _run_golden_path()
		"pointer":
			await _run_pointer_and_direct_control()
		"combat":
			await _run_combat_feedback()
		"modal":
			await _run_device_and_modal_roundtrip()
		_:
			push_error("unknown R9 dynamic diagnostic mode: %s" % _mode)
			_finish(1)
			return
	print(JSON.stringify({"ok": true, "mode": _mode, "kind": "automated_dynamic_diagnostic"}))
	_finish(0)


func _run_golden_path() -> void:
	var title := _game_root.scene_stack.current_scene() as TitleGameScene
	if title == null:
		push_error("golden diagnostic expected the title scene")
		return
	title._start_story()
	await _wait_frames(75)
	var scene := _current_map()
	if scene == null:
		push_error("golden diagnostic expected the lantern pass")
		return
	Input.action_press(&"move_north")
	await _wait_frames(55)
	Input.action_release(&"move_north")
	Input.action_press(&"move_west")
	await _wait_frames(30)
	Input.action_release(&"move_west")
	var keeper := scene.get_node(^"WorldRoot/LanternKeeper") as Node3D
	scene.player_3d.global_position = keeper.global_position + Vector3(1.1, 0.0, 0.0)
	scene._update_camera(0.0)
	scene._refresh_interaction_prompt()
	await _wait_frames(35)
	scene._on_player_interact_3d()
	await _finish_dialogue(240)
	var source := scene.get_node(
		^"WorldRoot/EncounterSources/FirstPack"
	) as EncounterSource3D
	scene.run_encounter_source(source)
	await _wait_frames(180)
	if scene.has_active_battle():
		scene.escape_battle()
	await _finish_dialogue(180)
	await _wait_frames(20)
	_open_menu()
	await _wait_frames(60)
	var menu := _game_root.scene_stack.current_scene() as MenuGameScene
	if menu != null:
		menu._open_settings()
	await _wait_frames(90)
	_close_top_scene()
	await _wait_frames(30)
	_close_top_scene()
	await _wait_frames(45)


func _run_pointer_and_direct_control() -> void:
	_start_new_game()
	await _wait_frames(75)
	var scene := _current_map()
	if scene == null:
		return
	var ground_target := scene.player_3d.global_position + Vector3(3.4, 0.0, -3.6)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = scene.camera_3d.unproject_position(ground_target)
	click.pressed = true
	scene._unhandled_input(click)
	click.pressed = false
	scene._unhandled_input(click)
	await _wait_frames(120)
	Input.action_press(&"move_east")
	await _wait_frames(65)
	Input.action_release(&"move_east")
	await _wait_frames(20)
	scene._show_navigation_failure(scene.player_3d.global_position + Vector3(12.0, 0.0, 12.0))
	await _wait_frames(55)
	var keeper := scene.get_node(^"WorldRoot/LanternKeeper") as Node3D
	scene._begin_pointer_interaction(
		keeper.get_node(^"Interactable") as StoryInteractable3D
	)
	await _wait_frames(150)
	await _finish_dialogue(180)
	await _wait_frames(30)


func _run_combat_feedback() -> void:
	_start_new_game()
	await _wait_frames(75)
	var scene := _current_map()
	if scene == null:
		return
	var source := scene.get_node(
		^"WorldRoot/EncounterSources/FirstPack"
	) as EncounterSource3D
	scene.set("_active_source", source)
	source.triggering = true
	var session := scene.begin_battle(source.encounter)
	scene.player_3d.global_position = Vector3(0.0, 0.05, 32.0)
	scene._update_camera(0.0)
	await _wait_frames(45)
	var target := session.enemies[0]
	scene.request_battle_action(
		BattleActionIntent.basic_attack(session.player.id, target.id)
	)
	await _wait_frames(105)
	var leader := _game_root.game_run.party.leader()
	if leader != null and not leader.skill_ids.is_empty():
		var skill := _game_root.content_database.skill(leader.skill_ids[0])
		scene.request_battle_action(
			BattleActionIntent.use_skill(session.player.id, skill, target.id)
		)
	await _wait_frames(130)
	scene.request_battle_action(BattleActionIntent.dodge(session.player.id))
	await _wait_frames(90)
	if leader != null and not leader.skill_ids.is_empty():
		session.player.mp = 0
		var rejected_skill := _game_root.content_database.skill(leader.skill_ids[0])
		var rejection := scene.request_battle_action(
			BattleActionIntent.use_skill(session.player.id, rejected_skill, target.id)
		)
		scene.map_hud.show_rejection(rejection.rejection)
	await _wait_frames(90)
	if scene.has_active_battle():
		scene.escape_battle()
	await _finish_dialogue(180)
	await _wait_frames(90)


func _run_device_and_modal_roundtrip() -> void:
	_start_new_game()
	await _wait_frames(75)
	var scene := _current_map()
	if scene == null:
		return
	var gamepad_event := InputEventJoypadButton.new()
	gamepad_event.button_index = JOY_BUTTON_START
	gamepad_event.pressed = true
	scene._input(gamepad_event)
	await _wait_frames(40)
	_open_menu()
	await _wait_frames(70)
	var menu := _game_root.scene_stack.current_scene() as MenuGameScene
	if menu != null:
		menu._open_settings()
	await _wait_frames(60)
	var settings := _game_root.scene_stack.current_scene() as SettingsGameScene
	if settings != null:
		settings._show_category(SettingsGameScene.SettingsCategory.CONTROLS)
		settings.action_list.select(SettingsService.REBINDABLE_ACTIONS.find(&"combat_item"))
		settings._begin_rebind()
	await _wait_frames(55)
	if settings != null:
		var conflict := InputEventKey.new()
		conflict.physical_keycode = KEY_M
		conflict.pressed = true
		settings._input(conflict)
	await _wait_frames(70)
	_close_top_scene()
	await _wait_frames(35)
	_game_root.save_service.configure_slots_directory(TEMP_SAVE_DIR)
	_game_root.save_service.save_slot(_game_root.game_run, 1)
	menu = _game_root.scene_stack.current_scene() as MenuGameScene
	if menu != null:
		menu._open_load()
	await _wait_frames(80)
	_close_top_scene()
	await _wait_frames(35)
	_close_top_scene()
	await _wait_frames(45)
	_clear_temp_saves()


func _start_new_game() -> void:
	_game_root.start_new_game()


func _current_map() -> MapGameScene3D:
	return _game_root.scene_stack.current_scene() as MapGameScene3D


func _open_menu() -> void:
	var event := InputEventAction.new()
	event.action = &"menu"
	event.pressed = true
	_game_root._unhandled_input(event)


func _close_top_scene() -> void:
	var current := _game_root.scene_stack.current_scene()
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	if current is MenuGameScene:
		(current as MenuGameScene)._unhandled_input(event)
	elif current is SettingsGameScene:
		(current as SettingsGameScene)._unhandled_input(event)
	elif current is SaveLoadGameScene:
		(current as SaveLoadGameScene)._unhandled_input(event)


func _finish_dialogue(max_frames: int) -> void:
	for frame: int in range(max_frames):
		if not _game_root.dialogue_layer.is_active():
			return
		if frame % 18 == 0:
			if _game_root.dialogue_layer.is_waiting_for_option():
				var options := _game_root.dialogue_layer.option_container.get_children()
				if not options.is_empty():
					(options[0] as Button).pressed.emit()
			else:
				_game_root.dialogue_layer.advance_requested.emit()
		await process_frame


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _clear_temp_saves() -> void:
	var directory := DirAccess.open(TEMP_SAVE_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)


func _finish(exit_code: int) -> void:
	Input.action_release(&"move_north")
	Input.action_release(&"move_west")
	Input.action_release(&"move_east")
	Input.action_release(&"move_south")
	_clear_temp_saves()
	if _game_root != null:
		for child: Node in _game_root.find_children("*", "", true, false):
			if child is MapGameScene3D:
				(child as MapGameScene3D)._clear_custom_cursors()
	_quit_after_cleanup(exit_code)


func _quit_after_cleanup(exit_code: int) -> void:
	await _wait_frames(3)
	quit(exit_code)
