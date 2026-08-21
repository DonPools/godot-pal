class_name GameRootIntegrationTestSuiteBase
extends RefCounted

const TEST_SAVE := "res://tests/.tmp_roadside_save.json"

var _scene_tree: SceneTree
var _failures: PackedStringArray = []


func _start_game_root() -> GameRoot:
	var packed := load("res://game/bootstrap/game_root.tscn") as PackedScene
	var game_root := packed.instantiate() as GameRoot
	_scene_tree.root.add_child(game_root)
	await _scene_tree.process_frame
	game_root.start_new_game()
	await _scene_tree.process_frame
	await _scene_tree.process_frame
	return game_root


func _dispose_game_root(game_root: GameRoot) -> void:
	if game_root != null and is_instance_valid(game_root):
		game_root.queue_free()
	await _scene_tree.process_frame


func _test_encounter() -> BattleEncounter:
	return TestContentFixtures.encounter()


func _finish_test_battle(session: BattleSession, map_scene: MapGameScene) -> void:
	if session == null or map_scene == null or not map_scene.has_active_battle():
		return
	var request := map_scene.request_battle_action(
		BattleActionIntent.basic_attack(session.player.id)
	)
	_expect(request.accepted(), "map-local battle should accept the player's basic attack")
	for _step: int in range(120):
		if (
			session.player.current_action != null
			and session.player.current_action.phase == BattleActionState.Phase.ACTIVE
		):
			break
		map_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
	map_scene.resolve_battle_hit(
		session.player.id,
		request.action_instance_id,
		session.enemies[0].id
	)


func _defeat_test_player(session: BattleSession, map_scene: MapGameScene) -> void:
	if session == null or map_scene == null or not map_scene.has_active_battle():
		return
	session.player.hp = 1
	var enemy := session.enemies[0]
	var request := map_scene.request_battle_action(
		BattleActionIntent.basic_attack(enemy.id, session.player.id)
	)
	for _step: int in range(120):
		if (
			enemy.current_action != null
			and enemy.current_action.phase == BattleActionState.Phase.ACTIVE
		):
			break
		map_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
	map_scene.resolve_battle_hit(enemy.id, request.action_instance_id, session.player.id)


func _mouse_button_event(
	position: Vector2,
	pressed: bool,
	shift_pressed: bool = false,
	ctrl_pressed: bool = false
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	event.ctrl_pressed = ctrl_pressed
	return event


func _wait_for_navigation_ready(player: PlayerCharacter3D) -> bool:
	for _physics_step: int in range(12):
		var navigation_map := player.navigation_agent.get_navigation_map()
		if navigation_map.is_valid():
			var closest := NavigationServer3D.map_get_closest_point(
				navigation_map,
				player.global_position
			)
			if closest.distance_to(player.global_position) <= PlayerCharacter3D.NAVIGATION_SNAP_LIMIT:
				return true
		await _scene_tree.physics_frame
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
