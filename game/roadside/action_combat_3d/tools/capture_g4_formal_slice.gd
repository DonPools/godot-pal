extends SceneTree

const OUTPUT_DIR := "/tmp/godot-pal-g4"
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
	await _wait_frames(3)
	var scene := await _enter_combat_map()
	_pause_combat_nodes(scene)
	await _capture("01_exploration")
	var source := _source(scene)
	var session := _begin_direct_encounter(scene, source)
	await _capture("02_alert")
	var ranged := session.enemies[2]
	var ranged_request := scene.request_battle_action(
		BattleActionIntent.basic_attack(ranged.id, session.player.id)
	)
	await _capture("03_windup")
	_advance_until_active(scene, session, ranged)
	await _wait_frames(5)
	await _capture("04_projectile_obstruction")
	_advance_until_idle(scene, session, ranged)
	var impact_target := session.enemies[0]
	var impact_request := scene.request_battle_action(
		BattleActionIntent.basic_attack(session.player.id, impact_target.id)
	)
	_advance_until_active(scene, session, session.player)
	scene.resolve_battle_hit(
		session.player.id, impact_request.action_instance_id, impact_target.id
	)
	await _capture("05_hit_feedback")
	_advance_until_idle(scene, session, session.player)
	await _defeat_all(scene, session)
	var story := source.binding.event as StoryModule
	_game_root.game_run.story.set_stage(story.id, &"cleared")
	_game_root.game_run.world.complete(scene.map_id, source.persistent_id)
	source.apply_completed()
	scene._refresh_objective()
	await _capture("06_victory")

	scene = await _enter_combat_map()
	_pause_combat_nodes(scene)
	source = _source(scene)
	_begin_direct_encounter(scene, source)
	scene.escape_battle()
	await _capture("07_escaped")

	scene = await _enter_combat_map()
	_pause_combat_nodes(scene)
	source = _source(scene)
	session = _begin_direct_encounter(scene, source)
	session.player.hp = 1
	var attacker := session.enemies[0]
	var defeat_request := scene.request_battle_action(
		BattleActionIntent.basic_attack(attacker.id, session.player.id)
	)
	_advance_until_active(scene, session, attacker)
	scene.resolve_battle_hit(attacker.id, defeat_request.action_instance_id, session.player.id)
	await _capture("08_defeat")
	print("G4 screenshots written to %s" % OUTPUT_DIR)
	var current_scene := _game_root.scene_stack.current_scene() as MapGameScene3D
	if current_scene != null:
		current_scene.pointer_controller.clear_custom_cursors()
	_game_root.queue_free()
	await _wait_frames(2)
	quit(0)


func _clear_previous_captures() -> void:
	var directory := DirAccess.open(OUTPUT_DIR)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		if file_name.get_extension().to_lower() == "png":
			directory.remove(file_name)


func _enter_combat_map() -> MapGameScene3D:
	var map := _game_root.content_database.map(&"map.roadside.north_slope_pack")
	_game_root.travel_to(map, map.default_spawn_id)
	await _wait_frames(4)
	return _game_root.scene_stack.current_scene() as MapGameScene3D


func _source(scene: MapGameScene3D) -> EncounterSource3D:
	return scene.get_node(
		^"WorldRoot/EncounterSources/NorthSlopePackSource"
	) as EncounterSource3D


func _begin_direct_encounter(
	scene: MapGameScene3D,
	source: EncounterSource3D
) -> BattleSession:
	return scene.begin_encounter_source_battle(source)


func _pause_combat_nodes(scene: MapGameScene3D) -> void:
	scene.set_process(false)
	scene.player_3d.set_physics_process(false)
	for enemy_view: EnemyActorView3D in scene.enemy_views():
		enemy_view.set_physics_process(false)


func _advance_until_active(
	scene: MapGameScene3D,
	session: BattleSession,
	actor: BattleActorState
) -> void:
	for _step: int in range(180):
		if actor.current_action != null and actor.current_action.phase == BattleActionState.Phase.ACTIVE:
			return
		scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)


func _advance_until_idle(
	scene: MapGameScene3D,
	session: BattleSession,
	actor: BattleActorState
) -> void:
	for _step: int in range(180):
		if actor.current_action == null or session.finished:
			return
		scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)


func _defeat_all(scene: MapGameScene3D, session: BattleSession) -> void:
	for target: BattleActorState in session.enemies:
		if session.finished:
			return
		target.hp = 1
		var request := scene.request_battle_action(
			BattleActionIntent.basic_attack(session.player.id, target.id)
		)
		if not request.accepted():
			_advance_until_idle(scene, session, session.player)
			request = scene.request_battle_action(
				BattleActionIntent.basic_attack(session.player.id, target.id)
			)
		_advance_until_active(scene, session, session.player)
		scene.resolve_battle_hit(session.player.id, request.action_instance_id, target.id)
		_advance_until_idle(scene, session, session.player)


func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var path := OUTPUT_DIR.path_join("%s.png" % name)
	var error := image.save_png(path)
	if error != OK:
		push_error("failed to save %s: %s" % [path, error_string(error)])


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame
