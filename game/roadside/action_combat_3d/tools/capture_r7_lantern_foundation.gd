extends SceneTree

const OUTPUT_DIR := "/tmp/godot-pal-r7"
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
		push_error("R7 capture expected new game to enter the lantern pass")
		_finish(1)
		return
	_freeze_map(scene)
	_focus_player(scene, Vector3(0.0, 0.05, 38.0))
	if await _capture("01_lantern_exploration") != OK:
		_finish(1)
		return

	var first_source := _source(scene, ^"WorldRoot/EncounterSources/FirstPack")
	_begin_direct_encounter(scene, first_source)
	_focus_player(scene, Vector3(0.0, 0.05, 32.0))
	scene._refresh_battle_hud()
	if await _capture("02_pack_combat") != OK:
		_finish(1)
		return
	scene.escape_battle()
	scene.result_label.visible = false

	var story := scene.story_module as LanternPassStory
	_open_dialogue(story.dialogue, &"gear_choice")
	await _advance_to_option()
	if await _capture("03_elite_equipment_choice") != OK:
		_finish(1)
		return
	_game_root.dialogue_layer.option_selected.emit(&"sword_seal")
	await _wait_dialogue_closed()

	var boss_source := _source(scene, ^"WorldRoot/EncounterSources/StoneBeast")
	var boss_session := _begin_direct_encounter(scene, boss_source)
	_focus_player(scene, Vector3(0.0, 0.05, -17.0))
	var boss_actor := boss_session.enemies[0]
	var charge := scene.request_battle_action(
		BattleActionIntent.charge(boss_actor.id, boss_session.player.id)
	)
	if not charge.accepted():
		push_error("R7 capture could not start the Boss charge")
		_finish(1)
		return
	scene._refresh_battle_hud()
	if await _capture("04_boss_charge_telegraph") != OK:
		_finish(1)
		return
	_advance_until_active(scene, boss_actor)
	scene.resolve_battle_pillar_contact(
		boss_actor.id,
		charge.action_instance_id,
		&"pillar.west"
	)
	if await _capture("05_pillar_stagger") != OK:
		_finish(1)
		return
	scene.escape_battle()
	scene.result_label.visible = false

	var array_entity := &"array.resolution"
	_game_root.game_run.flags.set_value(LanternPassStory.ARRAY_RESTORED)
	_game_root.game_run.flags.clear(LanternPassStory.ARRAY_SALVAGED)
	_game_root.game_run.story.set_stage(story.id, &"restored")
	_game_root.game_run.world.complete(scene.map_id, array_entity)
	scene.complete_entity(array_entity)
	scene._refresh_objective()
	_focus_player(scene, Vector3(0.0, 0.05, -29.0))
	if await _capture("06_array_restored") != OK:
		_finish(1)
		return

	_game_root.game_run.flags.clear(LanternPassStory.ARRAY_RESTORED)
	_game_root.game_run.flags.set_value(LanternPassStory.ARRAY_SALVAGED)
	_game_root.game_run.story.set_stage(story.id, &"salvaged")
	scene._refresh_world_state_views_3d()
	scene._refresh_objective()
	if await _capture("07_array_salvaged") != OK:
		_finish(1)
		return

	var leader := _game_root.game_run.party.leader()
	leader.realm_id = &"realm.foundation_establishment"
	leader.realm_layer = 1
	leader.foundation_id = &"foundation.sharp_metal"
	if &"skill.roadside.origin_sword_array" not in leader.skill_ids:
		leader.skill_ids.append(&"skill.roadside.origin_sword_array")
	_game_root.game_run.story.set_stage(story.id, &"foundation_established")
	scene.refresh_player_state()
	scene._refresh_objective()
	_focus_player(scene, Vector3(3.2, 0.05, -33.0))
	if await _capture("08_sharp_metal_foundation") != OK:
		_finish(1)
		return

	leader.foundation_id = &"foundation.flowing_water"
	scene.refresh_player_state()
	if await _capture("09_flowing_water_foundation") != OK:
		_finish(1)
		return

	var final_source := _source(
		scene,
		^"WorldRoot/EncounterSources/FoundationFinalTest"
	)
	_begin_direct_encounter(scene, final_source)
	_focus_player(scene, Vector3(0.0, 0.05, -40.0))
	scene._refresh_battle_hud()
	if await _capture("10_foundation_final_test") != OK:
		_finish(1)
		return

	print("R7 lantern-foundation screenshots written to %s" % OUTPUT_DIR)
	_finish(0)


func _clear_previous_captures() -> void:
	var directory := DirAccess.open(OUTPUT_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		if file_name.get_extension().to_lower() == "png":
			directory.remove(file_name)


func _source(scene: MapGameScene3D, path: NodePath) -> EncounterSource3D:
	return scene.get_node_or_null(path) as EncounterSource3D


func _begin_direct_encounter(
	scene: MapGameScene3D,
	source: EncounterSource3D
) -> BattleSession:
	if source == null:
		return null
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


func _advance_until_active(
	scene: MapGameScene3D,
	actor: BattleActorState
) -> void:
	for _step: int in range(180):
		if (
			actor.current_action != null
			and actor.current_action.phase == BattleActionState.Phase.ACTIVE
		):
			return
		scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)


func _open_dialogue(dialogue: DialogueDefinition, block_id: StringName) -> void:
	await _game_root.dialogue_layer.show_dialogue(dialogue, block_id)


func _advance_to_option() -> void:
	for _frame: int in range(600):
		if _game_root.dialogue_layer.is_waiting_for_option():
			return
		if _game_root.dialogue_layer.is_active():
			_game_root.dialogue_layer.advance_requested.emit()
		await process_frame
	push_error("R7 capture timed out waiting for a dialogue option")


func _wait_dialogue_closed() -> void:
	for _frame: int in range(240):
		if not _game_root.dialogue_layer.is_active():
			return
		await process_frame
	push_error("R7 capture timed out closing dialogue")


func _capture(name: String) -> Error:
	await process_frame
	if _game_root.dialogue_layer.is_active():
		_game_root.dialogue_layer.complete_typing()
	await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	if image == null or image.get_size() != Vector2i(640, 360):
		push_error("unexpected R7 capture image")
		return ERR_INVALID_DATA
	return image.save_png(OUTPUT_DIR.path_join("%s.png" % name))


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _finish(exit_code: int) -> void:
	var current_scene := _game_root.scene_stack.current_scene() as MapGameScene3D
	if current_scene != null:
		current_scene._clear_custom_cursors()
	_game_root.queue_free()
	_quit_after_cleanup(exit_code)


func _quit_after_cleanup(exit_code: int) -> void:
	await _wait_frames(2)
	quit(exit_code)
