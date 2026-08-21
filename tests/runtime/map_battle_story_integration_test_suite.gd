class_name MapBattleStoryIntegrationTestSuite
extends GameRootIntegrationTestSuiteBase


func run(scene_tree: SceneTree) -> PackedStringArray:
	_scene_tree = scene_tree
	await _test_map_battle_and_story()
	return _failures


func _test_map_battle_and_story() -> void:
	var game_root := await _start_game_root()
	var map_scene := game_root.scene_stack.current_scene() as MapGameScene3D
	var open_menu := InputEventAction.new()
	open_menu.action = &"menu"
	open_menu.pressed = true
	if map_scene != null:
		map_scene.set_process(false)
		var encounter := _test_encounter()
		var result_holder: Dictionary = {}
		map_scene.battle_finished.connect(func(result: BattleResult) -> void:
			result_holder["result"] = result
		)
		var session := map_scene.begin_battle(encounter)
		_expect(
			session != null
			and map_scene.has_active_battle()
			and game_root.scene_stack.scene_count() == 1,
			"map-local combat should own one BattleSession without pushing GameSceneStack"
		)
		_expect(
			map_scene.player_3d.control_enabled and not map_scene.player_3d.interaction_enabled,
			"active combat should allow movement while suppressing interaction"
		)
		game_root._unhandled_input(open_menu)
		_expect(
			game_root.scene_stack.current_scene() == map_scene
			and game_root.scene_stack.scene_count() == 1,
			"active combat should reject equipment and loadout menu entry"
		)
		var blocked_save := game_root.save_service.save_run(game_root.game_run, TEST_SAVE)
		_expect(
			blocked_save == ERR_BUSY
			and game_root.save_service.last_diagnostic.get("code")
			== "save_blocked_active_battle",
			"SaveService should return a stable active-battle rejection"
		)
		_finish_test_battle(session, map_scene)
		var direct_result := result_holder.get("result") as BattleResult
		_expect(
			direct_result != null
			and direct_result.is_victory()
			and direct_result.committed
			and not map_scene.has_active_battle()
			and map_scene.player_3d.interaction_enabled,
			"map-local Victory should commit once and restore exploration control"
		)
		var story_source := &"encounter.test.story_source"
		var battle_event := BattleTriggerEvent.new()
		battle_event.encounter = _test_encounter()
		var binding := StoryBinding.new()
		binding.event = battle_event
		binding.trigger_id = &"default"
		map_scene.battle_started.connect(_finish_test_battle.bind(map_scene), CONNECT_ONE_SHOT)
		await game_root.story_director.run_binding(
			binding,
			StoryOrigin.create(map_scene.map_id, story_source),
			map_scene
		)
		_expect(
			game_root.game_run.world.is_completed(map_scene.map_id, story_source)
			and not game_root.story_director.is_busy()
			and map_scene.player_3d.control_enabled
			and map_scene.player_3d.interaction_enabled
			and game_root.scene_stack.scene_count() == 1,
			"StoryDirector should await map combat, complete the source, and restore its lock"
		)
		var unhandled_event := UnhandledBattleTestEvent.new()
		unhandled_event.encounter = _test_encounter()
		var unhandled_binding := StoryBinding.new()
		unhandled_binding.event = unhandled_event
		unhandled_binding.trigger_id = &"default"
		var blocked_holder: Dictionary = {}
		game_root.story_director.control_restore_blocked.connect(
			func(reason: String) -> void: blocked_holder["reason"] = reason,
			CONNECT_ONE_SHOT
		)
		map_scene.battle_started.connect(_defeat_test_player.bind(map_scene), CONNECT_ONE_SHOT)
		await game_root.story_director.run_binding(
			unhandled_binding,
			StoryOrigin.create(map_scene.map_id, &"encounter.test.unhandled"),
			map_scene
		)
		_expect(
			String(blocked_holder.get("reason", "")).contains("Defeat"),
			"an unhandled Defeat should emit a stable control-lock diagnostic"
		)
		_expect(
			not map_scene.player_3d.control_enabled and not map_scene.player_3d.interaction_enabled,
			"an unhandled Defeat should keep exploration control locked"
		)
		for actor_state: ActorState in game_root.game_run.party.members:
			var actor_definition := game_root.content_database.actor(actor_state.definition_id)
			if actor_definition != null:
				actor_state.hp = CultivationRules.max_hp(
					actor_definition,
					actor_state,
					game_root.content_database
				)
				actor_state.mp = CultivationRules.max_mp(
					actor_definition,
					actor_state,
					game_root.content_database
				)
		map_scene.set_player_control_enabled(true)
	await _dispose_game_root(game_root)
