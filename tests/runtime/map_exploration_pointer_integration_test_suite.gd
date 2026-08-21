class_name MapExplorationPointerIntegrationTestSuite
extends GameRootIntegrationTestSuiteBase


func run(scene_tree: SceneTree) -> PackedStringArray:
	_scene_tree = scene_tree
	await _test_exploration_pointer()
	return _failures


func _test_exploration_pointer() -> void:
	var game_root := await _start_game_root()
	var map_scene := game_root.scene_stack.current_scene() as MapGameScene3D
	var shop := game_root.content_database.map(&"map.roadside.shop")
	game_root.travel_to(shop, shop.default_spawn_id)
	await _scene_tree.process_frame
	await _scene_tree.process_frame
	map_scene = game_root.scene_stack.current_scene() as MapGameScene3D
	if map_scene != null:
		_expect(
			await _wait_for_navigation_ready(map_scene.player_3d),
			"shop navigation map should synchronize before pointer input"
		)
		var shopkeeper := map_scene.get_node(^"WorldRoot/Shopkeeper") as NpcCharacter3D
		map_scene.camera_3d.refresh_immediately()
		var ground_target := map_scene.player_3d.global_position + Vector3(2.5, 0.0, 0.8)
		var ground_press := _mouse_button_event(
			map_scene.camera_3d.unproject_position(ground_target),
			true
		)
		map_scene._unhandled_input(ground_press)
		_expect(
			map_scene.player_3d.is_navigating()
			and map_scene.player_3d.navigation_target_position().distance_to(
				Vector3(ground_target.x, map_scene.player_3d.global_position.y, ground_target.z)
			) < 0.4,
			"left-clicking open ground should start PlayerCharacter3D navigation"
		)
		map_scene._unhandled_input(_mouse_button_event(ground_press.position, false))
		Input.action_press(&"move_east")
		map_scene.player_3d._physics_process(BattleSession.FIXED_STEP_SECONDS)
		Input.action_release(&"move_east")
		var player_animation := map_scene.player_3d.animation_player()
		_expect(
			not map_scene.player_3d.is_navigating()
			and map_scene.player_3d.current_animation_name() == &"run"
			and player_animation != null
			and String(player_animation.current_animation).get_file() == "run",
			"direct WASD input should cancel pointer navigation and enter the run pose, got %s"
			% [[
				map_scene.player_3d.current_animation_name(),
				player_animation.get_animation_list() if player_animation != null else [],
			]]
		)
		map_scene.player_3d._physics_process(BattleSession.FIXED_STEP_SECONDS)
		_expect(
			map_scene.player_3d.current_animation_name() == &"idle"
			and String(player_animation.current_animation).get_file() == "idle",
			"stopping direct movement should return the traveler to the relaxed idle pose"
		)
		map_scene.player_3d.position = shopkeeper.position + Vector3(-1.5, 0, 0)
		map_scene.camera_3d.refresh_immediately()
		var shopkeeper_interactable := shopkeeper.get_node(^"Interactable") as StoryInteractable3D
		_expect(
			shopkeeper_interactable.get_collision_layer_value(
				PointerTarget3D.POINTER_COLLISION_LAYER
			),
			"StoryInteractable3D should expose a physics pointer target layer"
		)
		_expect(
			map_scene.player_3d.navigate_to(Vector3(500.0, 0.0, 500.0))
			== PlayerCharacter3D.NavigationStartResult.UNREACHABLE,
			"navigation should reject destinations too far from the navigation surface"
		)
		map_scene.pointer_controller.navigate_to_interactable(shopkeeper_interactable)
		map_scene.pointer_controller.handle_navigation_failure(
			Vector3(500.0, 0.0, 500.0),
			PlayerCharacter3D.NavigationFailure.STALLED
		)
		_expect(
			map_scene.pointer_feedback.failure_marker.visible
			and map_scene.pointer_feedback.failure_label.visible
			and map_scene.map_hud.feedback_label.visible
			and map_scene.map_hud.feedback_label.text == "无法到达"
			and map_scene.pointer_controller.current_interaction_target() == null
			and not map_scene.player_3d.is_navigating(),
			"interrupted pointer navigation should clear intent and show world plus HUD feedback"
		)
		var interact_press := _mouse_button_event(
			map_scene.camera_3d.unproject_position(
				shopkeeper_interactable.global_position + Vector3.UP * 0.65
			),
			true
		)
		map_scene._unhandled_input(interact_press)
		map_scene.pointer_controller.update_intent()
		await _scene_tree.process_frame
		_expect(
			game_root.dialogue_layer.is_active(),
			"left-clicking a nearby NPC should open its formal dialogue"
		)
		map_scene._unhandled_input(_mouse_button_event(interact_press.position, false))
		while game_root.story_director.is_busy():
			if game_root.dialogue_layer.is_waiting_for_option():
				game_root.dialogue_layer.option_selected.emit(&"later")
			elif game_root.dialogue_layer.is_active():
				game_root.dialogue_layer.advance_requested.emit()
			await _scene_tree.process_frame
		_expect(not game_root.story_director.is_busy(), "dialogue should restore player control")
		map_scene.capture_location()
		game_root.scene_stack.push(game_root.menu_scene)
		await _scene_tree.process_frame
		_expect(game_root.scene_stack.scene_count() == 2, "menu should push over the map")
		game_root.scene_stack.pop()
		await _scene_tree.process_frame
		_expect(game_root.scene_stack.current_scene() == map_scene, "menu should return to map")
	await _dispose_game_root(game_root)
