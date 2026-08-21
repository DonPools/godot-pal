class_name MapCombatPresentationIntegrationTestSuite
extends GameRootIntegrationTestSuiteBase


func run(scene_tree: SceneTree) -> PackedStringArray:
	_scene_tree = scene_tree
	await _test_combat_presentation()
	return _failures


func _test_combat_presentation() -> void:
	var game_root := await _start_game_root()
	var combat_map := game_root.content_database.map(&"map.roadside.north_slope_pack")
	game_root.travel_to(combat_map, combat_map.default_spawn_id)
	await _scene_tree.process_frame
	await _scene_tree.process_frame
	var combat_scene := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		combat_scene != null
		and combat_scene.player_3d != null
		and combat_scene.camera_3d.projection == Camera3D.PROJECTION_ORTHOGONAL
		and combat_scene.enemy_views().size() == 3,
		"formal 3D map should compose the fixed camera, player, and finite enemy group"
	)
	if combat_scene != null:
		var source := combat_scene.get_node(
			^"WorldRoot/EncounterSources/NorthSlopePackSource"
		) as EncounterSource3D
		var session := combat_scene.begin_encounter_source_battle(source)
		_expect(
			await _wait_for_navigation_ready(combat_scene.player_3d),
			"combat navigation map should synchronize before pointer input"
		)
		_expect(
			session != null
			and combat_scene.has_active_battle()
			and combat_scene.battle_hud.visible,
			"formal 3D encounter should bind the map-owned BattleSession and HUD"
		)
		var basic_key_label := combat_scene.map_hud.get_node(
			^"BattlePanel/ActionBar/Margin/Slots/Basic/Rows/Key"
		) as Label
		var skill_one_key_label := combat_scene.map_hud.get_node(
			^"BattlePanel/ActionBar/Margin/Slots/SkillOne/Rows/Key"
		) as Label
		combat_scene._refresh_battle_hud()
		_expect(
			basic_key_label.text == "鼠左"
			and skill_one_key_label.text == "鼠右"
			and not combat_scene.map_hud.interaction_panel.visible,
			"keyboard/mouse battle HUD should show only its current device labels"
		)
		var device_gamepad := InputEventJoypadButton.new()
		device_gamepad.button_index = JOY_BUTTON_A
		device_gamepad.pressed = true
		combat_scene._input(device_gamepad)
		combat_scene._refresh_battle_hud()
		_expect(
			basic_key_label.text == "A" and skill_one_key_label.text == "X",
			"gamepad input should atomically replace keyboard/mouse action labels"
		)
		var device_keyboard := InputEventKey.new()
		device_keyboard.physical_keycode = KEY_W
		device_keyboard.pressed = true
		combat_scene._input(device_keyboard)
		combat_scene._refresh_battle_hud()
		_expect(
			basic_key_label.text == "鼠左" and skill_one_key_label.text == "鼠右",
			"keyboard input should restore keyboard/mouse labels without mixed prompts"
		)
		var pointer_enemy := source.enemy_views[0]
		var combat_player_animation := combat_scene.player_3d.animation_player()
		var feedback_request := combat_scene.request_battle_action(
			BattleActionIntent.basic_attack(session.player.id, pointer_enemy.actor_id)
		)
		for _step: int in range(120):
			if (
				session.player.current_action != null
				and session.player.current_action.phase == BattleActionState.Phase.ACTIVE
			):
				break
			combat_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		combat_scene.resolve_battle_hit(
			session.player.id,
			feedback_request.action_instance_id,
			pointer_enemy.actor_id
		)
		_expect(
			feedback_request.accepted()
			and combat_scene.is_hit_stop_active()
			and combat_scene.combat_feedback.active_effect_count() >= 2
			and combat_scene.player_3d.current_animation_name() == &"attack"
			and combat_player_animation != null
			and String(combat_player_animation.current_animation).get_file() == "attack",
			"confirmed damage should create local hit-stop, sword arc, hit spark, and flash feedback; pose=%s"
			% [combat_scene.player_3d.current_animation_name()]
		)
		combat_scene._process(0.2)
		game_root.settings_service.set_accessibility(48.0, true, false)
		combat_scene.start_hit_stop(MapGameScene3D.ENEMY_HIT_STOP_SECONDS)
		_expect(
			is_equal_approx(
				combat_scene.hit_stop_remaining_seconds(),
				MapGameScene3D.ENEMY_HIT_STOP_SECONDS
				* MapGameScene3D.REDUCED_HIT_STOP_SCALE
			),
			"reduced-flash mode should retain readable but shortened local hit-stop"
		)
		combat_scene.restore_hit_stop_motion()
		var transient_motion := Node.new()
		combat_scene.add_child(transient_motion)
		transient_motion.add_to_group(&"battle_motion_3d")
		transient_motion.set_physics_process(true)
		combat_scene.start_hit_stop(MapGameScene3D.ENEMY_HIT_STOP_SECONDS)
		transient_motion.free()
		combat_scene.restore_hit_stop_motion()
		_expect(
			not combat_scene.is_hit_stop_active()
			and combat_scene.paused_battle_motion_count() == 0,
			"hit-stop restoration should ignore battle motion freed before the pause ends"
		)
		game_root.settings_service.set_accessibility(48.0, false, false)
		while session.player.current_action != null:
			combat_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		_expect(
			combat_scene.player_3d.current_animation_name() == &"idle"
			and String(combat_player_animation.current_animation).get_file() == "idle",
			"finished player attacks should recover directly to idle"
		)
		var visual_event := BattleEvent.new()
		visual_event.kind = BattleEvent.Kind.ACTION_STARTED
		visual_event.actor_id = session.player.id
		visual_event.action_id = &"skill.test.cast"
		combat_scene.player_3d.handle_battle_event(visual_event)
		_expect(
			combat_scene.player_3d.current_animation_name() == &"cast"
			and String(combat_player_animation.current_animation).get_file() == "cast",
			"skill actions should enter the cast animation instead of a binding pose, got %s"
			% [combat_scene.player_3d.current_animation_name()]
		)
		visual_event = BattleEvent.new()
		visual_event.kind = BattleEvent.Kind.DAMAGE
		visual_event.target_id = session.player.id
		combat_scene.player_3d.handle_battle_event(visual_event)
		_expect(
			combat_scene.player_3d.current_animation_name() == &"hit"
			and String(combat_player_animation.current_animation).get_file() == "hit",
			"player damage should enter the hit animation"
		)
		visual_event = BattleEvent.new()
		visual_event.kind = BattleEvent.Kind.DEATH
		visual_event.actor_id = session.player.id
		combat_scene.player_3d.handle_battle_event(visual_event)
		_expect(
			combat_scene.player_3d.current_animation_name() == &"death"
			and String(combat_player_animation.current_animation).get_file() == "death",
			"player death should enter the death animation"
		)
		visual_event = BattleEvent.new()
		visual_event.kind = BattleEvent.Kind.ACTION_FINISHED
		visual_event.actor_id = session.player.id
		combat_scene.player_3d.handle_battle_event(visual_event)
		_expect(
			combat_scene.player_3d.current_animation_name() == &"idle",
			"visual recovery should return to idle without exposing the bind pose"
		)
		var telegraph_enemy := source.enemy_views[1]
		var telegraph_actor := session.actor(telegraph_enemy.actor_id)
		var telegraph_request := combat_scene.request_battle_action(
			BattleActionIntent.basic_attack(telegraph_actor.id, session.player.id)
		)
		var enemy_animation := telegraph_enemy.animation_player()
		var expected_enemy_animation := (
			"cast"
			if telegraph_enemy.definition.combat_style
			== EnemyDefinition.CombatStyle.RANGED
			else "attack"
		)
		_expect(
			telegraph_request.accepted()
			and telegraph_enemy.telegraph.visible
			and telegraph_enemy.telegraph.scale.length() > 0.1
			and telegraph_enemy.current_animation_name() == (
				&"cast"
				if telegraph_enemy.definition.combat_style
				== EnemyDefinition.CombatStyle.RANGED
				else &"attack"
			)
			and enemy_animation != null
			and String(enemy_animation.current_animation).get_file()
			== expected_enemy_animation,
			"enemy windup should expose a visible animated world-space telegraph"
		)
		while telegraph_actor.current_action != null:
			combat_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		combat_scene.player_3d.global_position = (
			pointer_enemy.global_position + Vector3(4.0, 0.0, 0.0)
		)
		combat_scene.camera_3d.refresh_immediately()
		var target_switch := InputEventAction.new()
		target_switch.action = &"combat_target_next"
		target_switch.pressed = true
		combat_scene._unhandled_input(target_switch)
		var first_soft_target := combat_scene.pointer_controller.current_soft_target()
		combat_scene._unhandled_input(target_switch)
		var second_soft_target := combat_scene.pointer_controller.current_soft_target()
		_expect(
			first_soft_target != null
			and second_soft_target != null
			and first_soft_target != second_soft_target
			and combat_scene.pointer_feedback.target_ring.visible,
			"target-switch input should cycle visible enemies and keep a world target ring"
		)
		combat_scene.pointer_controller.select_attack_target(null)
		combat_scene.camera_3d.refresh_immediately()
		var combat_camera_focus := combat_scene.camera_3d.focus_position()
		var target_camera_offset := (
			second_soft_target.global_position - combat_scene.player_3d.global_position
		)
		target_camera_offset.y = 0.0
		var expected_camera_focus := combat_scene.player_3d.global_position + (
			target_camera_offset.normalized()
			* minf(target_camera_offset.length() * 0.6, 3.2)
		)
		_expect(
			combat_camera_focus.distance_to(expected_camera_focus) < 0.01,
			"combat camera should bias toward the active target to keep both actors visible"
		)
		var enemy_screen_position := combat_scene.camera_3d.unproject_position(
			pointer_enemy.global_position + Vector3.UP * 0.85
		)
		var enemy_press := _mouse_button_event(enemy_screen_position, true)
		combat_scene._input(enemy_press)
		combat_scene._unhandled_input(enemy_press)
		combat_scene.pointer_controller.update_intent()
		combat_scene._refresh_battle_hud()
		_expect(
			combat_scene.player_3d.is_navigating()
			and session.player.current_action == null
			and combat_scene.pointer_feedback.target_ring.visible
			and combat_scene.map_hud.target_panel.visible
			and combat_scene.map_hud.target_name_label.text
			== pointer_enemy.definition.display_name,
			"left-clicking a distant enemy should chase it before attacking"
		)
		combat_scene.player_3d.global_position = (
			pointer_enemy.global_position + Vector3(1.0, 0.0, 0.0)
		)
		combat_scene.pointer_controller.update_intent()
		_expect(
			session.player.current_action != null
			and session.player.current_action.action_id == BattleSession.BASIC_ATTACK_ID,
			"pointer pursuit should issue one basic attack after entering range"
		)
		combat_scene._unhandled_input(_mouse_button_event(enemy_screen_position, false))
		for _step: int in range(90):
			if session.player.current_action == null:
				break
			combat_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		combat_scene.player_3d.global_position = (
			pointer_enemy.global_position + Vector3(4.0, 0.0, 0.0)
		)
		combat_scene.camera_3d.refresh_immediately()
		enemy_screen_position = combat_scene.camera_3d.unproject_position(
			pointer_enemy.global_position + Vector3.UP * 0.85
		)
		var force_move_ground: Variant = combat_scene.pointer_controller.screen_ground_point(
			enemy_screen_position
		)
		var force_move_press := _mouse_button_event(enemy_screen_position, true, false, true)
		combat_scene._unhandled_input(force_move_press)
		combat_scene.pointer_controller.update_intent()
		_expect(
			combat_scene.player_3d.is_navigating()
			and session.player.current_action == null
			and force_move_ground is Vector3
			and combat_scene.player_3d.navigation_target_position().distance_to(
				Vector3(
					(force_move_ground as Vector3).x,
					combat_scene.player_3d.global_position.y,
					(force_move_ground as Vector3).z
				)
			) < 0.4,
			"Ctrl plus left-click should force movement even over an enemy"
		)
		combat_scene._unhandled_input(
			_mouse_button_event(force_move_press.position, false, false, true)
		)
		var stand_attack_press := _mouse_button_event(
			enemy_screen_position,
			true,
			true
		)
		combat_scene._unhandled_input(stand_attack_press)
		combat_scene.pointer_controller.update_intent()
		_expect(
			not combat_scene.player_3d.is_navigating()
			and session.player.current_action != null
			and session.player.current_action.action_id == BattleSession.BASIC_ATTACK_ID,
			"Shift plus left-click should attack in place without chasing"
		)
		combat_scene._unhandled_input(
			_mouse_button_event(stand_attack_press.position, false, true)
		)
		for _step: int in range(90):
			if session.player.current_action == null:
				break
			combat_scene.advance_battle(BattleSession.FIXED_STEP_SECONDS)
		var gamepad_attack := InputEventJoypadButton.new()
		gamepad_attack.button_index = JOY_BUTTON_A
		gamepad_attack.pressed = true
		combat_scene.player_3d._unhandled_input(gamepad_attack)
		_expect(
			session.player.current_action != null
			and session.player.current_action.action_id == BattleSession.BASIC_ATTACK_ID,
			"formal gamepad mapping should request the same typed combat action"
		)
		var views_active := true
		for enemy_view: EnemyActorView3D in source.enemy_views:
			views_active = views_active and enemy_view.state == EnemyActorView3D.State.ACTIVE
		_expect(views_active, "formal enemy views should bind the same BattleSession")
		var escaped_result := combat_scene.escape_battle()
		_expect(
			escaped_result.outcome == BattleResult.Outcome.ESCAPED
			and not game_root.game_run.world.is_completed(
				combat_scene.map_id,
				source.persistent_id
			)
			and source.all_living_enemies_home()
			and not combat_scene.player_3d.is_navigating()
			and not combat_scene.pointer_feedback.target_ring.visible
			and not combat_scene.map_hud.target_panel.visible
			and combat_scene.pointer_controller.current_attack_target() == null
			and combat_scene.pointer_controller.current_soft_target() == null,
			"Escaped should keep the source while clearing navigation, target, pointer, and HUD state"
		)
	await _dispose_game_root(game_root)
