class_name LanternMapIntegrationTestSuite
extends GameRootIntegrationTestSuiteBase


func run(scene_tree: SceneTree) -> PackedStringArray:
	_scene_tree = scene_tree
	await _test_lantern_map()
	return _failures


func _test_lantern_map() -> void:
	var game_root := await _start_game_root()
	var leader := game_root.game_run.party.leader()
	CultivationRules.gain_cultivation(leader, 230, game_root.content_database)
	var catalyst := game_root.content_database.item(
		&"item.roadside.qi_eating_stone_heart"
	)
	game_root.game_run.inventory.add_item(catalyst, 1)
	var breakthrough := CultivationTransaction.breakthrough(
		game_root.game_run,
		game_root.content_database.foundation(&"foundation.sharp_metal"),
		catalyst,
		game_root.content_database
	)
	_expect(breakthrough.succeeded(), "GameRoot smoke should prepare a valid foundation build")
	var lantern_map := game_root.content_database.map(&"map.roadside.lantern_pass")
	game_root.travel_to(lantern_map, &"from_wilds")
	await _scene_tree.process_frame
	await _scene_tree.process_frame
	var lantern_scene := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		lantern_scene != null
		and lantern_scene.map_id == lantern_map.id
		and lantern_scene.story_module is LanternPassStory
		and lantern_scene.get_node(^"WorldRoot/EncounterSources").get_child_count() == 6
		and lantern_scene.enemy_views().size() == 38
		and lantern_scene.get_node_or_null(^"WorldRoot/Terrain/PineSouthEast") is StaticBody3D
		and lantern_scene.get_node_or_null(^"WorldRoot/Terrain/PineFinalWest") is StaticBody3D
		and lantern_scene.get_node_or_null(^"WorldRoot/SpawnPoints/from_wilds") is Marker3D
		and lantern_scene.get_node_or_null(^"WorldRoot/NavigationRegion3D") is NavigationRegion3D,
		"lantern pass should compose six encounters, roadside dressing, paired spawn, and navigation"
	)
	if lantern_scene != null:
		_expect(
			await _wait_for_navigation_ready(lantern_scene.player_3d),
			"lantern-pass navigation map should synchronize before route checks"
		)
		var navigation_map := lantern_scene.player_3d.navigation_agent.get_navigation_map()
		for source_name: StringName in [
			&"FirstPack", &"StoneBeast", &"FoundationFinalTest",
		]:
			var route_target := lantern_scene.get_node(
				NodePath("WorldRoot/EncounterSources/%s" % source_name)
			) as Node3D
			var route := NavigationServer3D.map_get_path(
				navigation_map,
				lantern_scene.player_3d.global_position,
				route_target.global_position,
				true,
				lantern_scene.player_3d.navigation_agent.navigation_layers
			)
			_expect(
				not route.is_empty()
				and route[route.size() - 1].distance_to(route_target.global_position) < 0.4,
				"lantern-pass navigation should connect from_wilds to %s" % source_name
			)
		var boss_source := lantern_scene.get_node(
			^"WorldRoot/EncounterSources/StoneBeast"
		) as EncounterSource3D
		var boss_session := lantern_scene.begin_encounter_source_battle(boss_source)
		lantern_scene._refresh_battle_hud()
		_expect(
			lantern_scene.map_hud.target_panel.visible
			and lantern_scene.map_hud.target_type_label.text == "首领"
			and lantern_scene.map_hud.target_hp_bar.max_value
			== boss_session.enemies[0].max_hp,
			"single charger encounters should expose a persistent boss health card"
		)
		var ultimate_input := InputEventAction.new()
		ultimate_input.action = &"combat_skill_three"
		ultimate_input.pressed = true
		lantern_scene.player_3d._unhandled_input(ultimate_input)
		_expect(
			boss_session.player.current_action != null
			and boss_session.player.current_action.action_id
			== &"skill.roadside.origin_sword_array",
			"foundation establishment should expose its third-slot ultimate in real map input"
		)
		while boss_session.player.current_action != null:
			lantern_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		var boss_actor := boss_session.enemies[0]
		var charge := lantern_scene.request_battle_action(
			BattleActionIntent.charge(boss_actor.id, boss_session.player.id)
		)
		for _step: int in range(120):
			if (
				boss_actor.current_action != null
				and boss_actor.current_action.phase == BattleActionState.Phase.ACTIVE
			):
				break
			lantern_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		var pillar_events := lantern_scene.resolve_battle_pillar_contact(
			boss_actor.id,
			charge.action_instance_id,
			&"pillar.west"
		)
		_expect(
			boss_session.is_pillar_used(&"pillar.west")
			and boss_actor.stagger_remaining_seconds > 0.0
			and not pillar_events.is_empty(),
			"formal lantern Boss should enter fixed-step stagger after an active pillar collision"
		)
		lantern_scene.escape_battle()
	await _dispose_game_root(game_root)
