class_name MapPointerController3D
extends Node

const INTERACTION_DISTANCE := 2.1
const INTERACTION_STOPPING_DISTANCE := 1.45
const BASIC_ATTACK_DISTANCE := 1.65

@export var move_cursor: Texture2D
@export var attack_cursor: Texture2D
@export var interact_cursor: Texture2D
@export var forbidden_cursor: Texture2D

var _attack_target: EnemyActorView3D
var _interaction_target: StoryInteractable3D
var _soft_target_selector := CombatTargetSelector3D.new()
var _pointer_picker := MapPointerPicker3D.new()

var _map_scene: MapGameScene3D
var _player: PlayerCharacter3D
var _camera: Camera3D
var _pointer_feedback: PointerFeedback3D
var _hud: MapHud3D
var _settings: SettingsService
var _using_pointer_aim: bool = true
var _primary_pointer_pressed: bool = false
var _queued_primary_attack: bool = false
var _stand_ground_attack: bool = false
var _pointer_attack_point := Vector3.ZERO
var _pointer_interaction_running: bool = false


func configure(
	map_scene: MapGameScene3D,
	player: PlayerCharacter3D,
	camera: Camera3D,
	pointer_feedback: PointerFeedback3D,
	hud: MapHud3D,
	settings: SettingsService
) -> void:
	_map_scene = map_scene
	_player = player
	_camera = camera
	_pointer_feedback = pointer_feedback
	_hud = hud
	_settings = settings
	_soft_target_selector.configure(player, camera)
	_pointer_picker.configure(player, camera)
	register_custom_cursors()


func update_pointer_state(delta: float) -> void:
	_update_aim(delta)
	update_intent()
	_update_cursor_context()


func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_using_pointer_aim = true
		_soft_target_selector.clear()
		_hud.set_input_device(false)
	elif event is InputEventKey:
		_hud.set_input_device(false)
	elif (
		event is InputEventJoypadMotion
		and absf(event.axis_value) > 0.25
		and event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]
	):
		_using_pointer_aim = false
		_hud.set_input_device(true)
	elif event is InputEventJoypadButton:
		_hud.set_input_device(true)


func handle_unhandled_input(event: InputEvent) -> void:
	if _player == null or not _player.control_enabled or _story_is_busy():
		return
	if event.is_action_pressed(&"combat_target_next") and _battle_session() != null:
		_using_pointer_aim = false
		_cycle_soft_target()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.is_action(&"combat_attack"):
			return
		_primary_pointer_pressed = mouse_event.pressed
		if mouse_event.pressed:
			_handle_primary_pointer(mouse_event)
		elif not _queued_primary_attack:
			_clear_pointer_attack(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _primary_pointer_pressed:
		if _attack_target == null and _interaction_target == null and not _stand_ground_attack:
			_begin_ground_navigation((event as InputEventMouseMotion).position)
			get_viewport().set_input_as_handled()


func cancel_pointer_intent(
	stop_navigation: bool = true,
	clear_primary_press: bool = true
) -> void:
	_clear_pointer_interaction(stop_navigation)
	_clear_pointer_attack(stop_navigation)
	if clear_primary_press:
		_primary_pointer_pressed = false
	if stop_navigation and _player != null:
		_player.stop_navigation()


func reset_pointer_state() -> void:
	_soft_target_selector.clear()
	cancel_pointer_intent()
	if _pointer_feedback != null:
		_pointer_feedback.clear_target()


func preferred_hud_target() -> EnemyActorView3D:
	for preferred: EnemyActorView3D in [
		_attack_target,
		_soft_target_selector.current_target(),
	]:
		if preferred != null and is_instance_valid(preferred) and not preferred.is_defeated():
			return preferred
	var only_living: EnemyActorView3D
	var living_count := 0
	for enemy_view: EnemyActorView3D in _enemy_views():
		if enemy_view.is_defeated():
			continue
		living_count += 1
		only_living = enemy_view
		if enemy_view.definition != null and enemy_view.definition.is_boss:
			return enemy_view
	return only_living if living_count == 1 else null


func navigate_to_interactable(interactable: StoryInteractable3D) -> void:
	cancel_pointer_intent(true, false)
	var result := _player.navigate_to(
		interactable.global_position,
		INTERACTION_STOPPING_DISTANCE
	)
	if _navigation_rejected(result):
		_show_navigation_failure(interactable.global_position)
		return
	_interaction_target = interactable
	_pointer_feedback.show_destination(
		_player.navigation_target_position()
		if result == PlayerCharacter3D.NavigationStartResult.STARTED
		else interactable.global_position,
		PointerFeedback3D.DestinationKind.INTERACT
	)


func update_intent() -> void:
	if _player == null or not _player.control_enabled or _story_is_busy():
		cancel_pointer_intent()
		return
	_update_pointer_interaction()
	_update_pointer_attack()


func screen_ground_point(screen_position: Vector2) -> Variant:
	return _pointer_picker.ground_point(screen_position)


func handle_navigation_failure(
	target: Vector3,
	_reason: PlayerCharacter3D.NavigationFailure
) -> void:
	cancel_pointer_intent()
	_show_navigation_failure(target)


func current_attack_target() -> EnemyActorView3D:
	return _attack_target


func current_interaction_target() -> StoryInteractable3D:
	return _interaction_target


func current_soft_target() -> EnemyActorView3D:
	return _soft_target_selector.current_target()


func select_attack_target(enemy: EnemyActorView3D) -> void:
	_attack_target = enemy
	if enemy != null and is_instance_valid(enemy) and not enemy.is_defeated():
		_pointer_feedback.set_target(enemy, _target_ring_radius(enemy))


func register_custom_cursors() -> void:
	if move_cursor != null:
		Input.set_custom_mouse_cursor(move_cursor, Input.CURSOR_ARROW, Vector2(3, 3))
	if attack_cursor != null:
		Input.set_custom_mouse_cursor(attack_cursor, Input.CURSOR_CROSS, Vector2(3, 3))
	if interact_cursor != null:
		Input.set_custom_mouse_cursor(
			interact_cursor,
			Input.CURSOR_POINTING_HAND,
			Vector2(3, 3)
		)
	if forbidden_cursor != null:
		Input.set_custom_mouse_cursor(
			forbidden_cursor,
			Input.CURSOR_FORBIDDEN,
			Vector2(3, 3)
		)


func clear_custom_cursors() -> void:
	for shape: Input.CursorShape in [
		Input.CURSOR_ARROW,
		Input.CURSOR_CROSS,
		Input.CURSOR_POINTING_HAND,
		Input.CURSOR_FORBIDDEN,
	]:
		Input.set_custom_mouse_cursor(null, shape)


func _update_aim(delta: float) -> void:
	if _player == null or not _player.control_enabled:
		return
	var deadzone := _settings.aim_deadzone if _settings != null else 0.25
	var sensitivity := _settings.aim_sensitivity if _settings != null else 1.0
	var stick := Input.get_vector(
		&"aim_west", &"aim_east", &"aim_north", &"aim_south", deadzone
	)
	if stick.length() > deadzone:
		var right := _camera.global_basis.x
		right.y = 0.0
		var forward := -_camera.global_basis.z
		forward.y = 0.0
		_soft_target_selector.clear()
		if _attack_target == null:
			_pointer_feedback.clear_target()
		_player.turn_aim_toward(
			right.normalized() * stick.x + forward.normalized() * -stick.y,
			1.0 - exp(-14.0 * sensitivity * maxf(delta, 0.0001))
		)
		return
	if _using_pointer_aim:
		_soft_target_selector.clear()
		if _attack_target == null:
			_pointer_feedback.clear_target()
		var mouse_position := get_viewport().get_mouse_position()
		var ray_origin := _camera.project_ray_origin(mouse_position)
		var ray_direction := _camera.project_ray_normal(mouse_position)
		if absf(ray_direction.y) > 0.0001:
			var distance := -ray_origin.y / ray_direction.y
			if distance > 0.0:
				_player.set_aim_direction(
					ray_origin + ray_direction * distance - _player.global_position
				)
		return
	var target_direction := _soft_target_selector.acquire_direction(
		_enemy_views(),
		_battle_session() != null
	)
	if not target_direction.is_zero_approx():
		_player.turn_aim_toward(
			target_direction,
			1.0 - exp(-10.0 * sensitivity * maxf(delta, 0.0001))
		)
		var soft_target := _soft_target_selector.current_target()
		if soft_target != null:
			_pointer_feedback.set_target(soft_target, _target_ring_radius(soft_target))
	elif not _player.movement_direction().is_zero_approx():
		_player.turn_aim_toward(
			_player.movement_direction(),
			1.0 - exp(-8.0 * sensitivity * maxf(delta, 0.0001))
		)
		_pointer_feedback.clear_target()
	else:
		_pointer_feedback.clear_target()


func _cycle_soft_target() -> void:
	var soft_target := _soft_target_selector.cycle(_enemy_views())
	if soft_target == null:
		_pointer_feedback.clear_target()
		_hud.show_notice(tr("UI_HUD_NO_TARGET_NEARBY"))
		return
	_player.set_aim_direction(soft_target.global_position - _player.global_position)
	_pointer_feedback.set_target(soft_target, _target_ring_radius(soft_target))
	_hud.show_notice(
		tr("UI_HUD_TARGET_LOCK_FORMAT") % (
			soft_target.definition.display_name
			if soft_target.definition != null
			else tr("UI_HUD_TARGET_FALLBACK")
		)
	)


func _handle_primary_pointer(event: InputEventMouseButton) -> void:
	var force_move := event.ctrl_pressed or Input.is_action_pressed(&"combat_force_move")
	var stand_ground := event.shift_pressed or Input.is_action_pressed(&"combat_stand_ground")
	if force_move:
		_begin_ground_navigation(event.position)
		return
	if _battle_session() != null:
		var enemy := _pointer_picker.enemy_at_screen(event.position, _enemy_views())
		if enemy != null:
			_begin_pointer_attack(enemy, stand_ground)
		elif stand_ground:
			_begin_stand_ground_attack(event.position)
		else:
			_begin_ground_navigation(event.position)
		return
	var interactable := _pointer_picker.interactable_at_screen(event.position)
	if interactable != null:
		navigate_to_interactable(interactable)
	else:
		_begin_ground_navigation(event.position)


func _begin_ground_navigation(screen_position: Vector2) -> void:
	var ground_point: Variant = screen_ground_point(screen_position)
	if ground_point == null:
		_show_navigation_failure(_pointer_picker.screen_plane_fallback(screen_position))
		return
	cancel_pointer_intent(true, false)
	var destination := ground_point as Vector3
	var result := _player.navigate_to(destination)
	if _navigation_rejected(result):
		_show_navigation_failure(destination)
		return
	_pointer_feedback.show_destination(
		_player.navigation_target_position()
		if result == PlayerCharacter3D.NavigationStartResult.STARTED
		else destination,
		PointerFeedback3D.DestinationKind.MOVE
	)


func _begin_pointer_attack(enemy: EnemyActorView3D, stand_ground: bool) -> void:
	cancel_pointer_intent(true, false)
	_attack_target = enemy
	_queued_primary_attack = true
	_stand_ground_attack = stand_ground
	_pointer_attack_point = enemy.global_position
	_pointer_feedback.set_target(enemy, _target_ring_radius(enemy))


func _begin_stand_ground_attack(screen_position: Vector2) -> void:
	var ground_point: Variant = screen_ground_point(screen_position)
	if ground_point == null:
		return
	cancel_pointer_intent(true, false)
	_pointer_attack_point = ground_point as Vector3
	_queued_primary_attack = true
	_stand_ground_attack = true
	_player.stop_navigation()
	_pointer_feedback.show_destination(
		_pointer_attack_point,
		PointerFeedback3D.DestinationKind.MOVE
	)


func _update_pointer_interaction() -> void:
	if _interaction_target == null or _pointer_interaction_running:
		return
	if not is_instance_valid(_interaction_target) or not _interaction_target.is_available():
		_clear_pointer_interaction()
		return
	if _player.global_position.distance_to(_interaction_target.global_position) > INTERACTION_DISTANCE:
		var navigation_result := _player.navigate_to(
			_interaction_target.global_position,
			INTERACTION_STOPPING_DISTANCE
		)
		if _navigation_rejected(navigation_result):
			var failed_target := _interaction_target.global_position
			_clear_pointer_interaction()
			_show_navigation_failure(failed_target)
		return
	var interactable := _interaction_target
	_clear_pointer_interaction(false)
	_pointer_interaction_running = true
	_run_pointer_interaction(interactable)


func _run_pointer_interaction(interactable: StoryInteractable3D) -> void:
	if _map_scene == null or not is_instance_valid(_map_scene):
		_pointer_interaction_running = false
		return
	await _map_scene.run_interactable(interactable)
	if is_instance_valid(self):
		_pointer_interaction_running = false


func _update_pointer_attack() -> void:
	var has_attack_intent := (
		_queued_primary_attack
		or _attack_target != null
		or _stand_ground_attack
	)
	if not has_attack_intent:
		return
	if not _queued_primary_attack and not _primary_pointer_pressed:
		_clear_pointer_attack(false)
		return
	var session := _battle_session()
	if session == null:
		_clear_pointer_attack()
		return
	var actor := session.player
	var target_position := _pointer_attack_point
	var target_id: StringName
	if _attack_target != null:
		if not is_instance_valid(_attack_target) or _attack_target.is_defeated():
			_clear_pointer_attack()
			return
		target_position = _attack_target.global_position
		target_id = _attack_target.actor_id
	var direction := target_position - _player.global_position
	direction.y = 0.0
	if direction.length_squared() > 0.001:
		_player.set_aim_direction(direction)
	var in_range := _stand_ground_attack or direction.length() <= BASIC_ATTACK_DISTANCE
	if not in_range:
		var navigation_result := _player.navigate_to(target_position, BASIC_ATTACK_DISTANCE)
		if _navigation_rejected(navigation_result):
			_clear_pointer_attack()
			_show_navigation_failure(target_position)
		return
	_player.stop_navigation()
	if not actor.can_act() or actor.cooldown_remaining(BattleSession.BASIC_ATTACK_ID) > 0.0:
		return
	var result := _map_scene.request_battle_action(
		BattleActionIntent.basic_attack(actor.id, target_id)
	)
	if result != null and result.accepted():
		_queued_primary_attack = false
		if not _primary_pointer_pressed:
			_clear_pointer_attack(false)


func _clear_pointer_interaction(stop_navigation: bool = true) -> void:
	_interaction_target = null
	if stop_navigation and _player != null:
		_player.stop_navigation()


func _clear_pointer_attack(stop_navigation: bool = true) -> void:
	_attack_target = null
	_queued_primary_attack = false
	_stand_ground_attack = false
	if _pointer_feedback != null:
		_pointer_feedback.clear_target()
	if stop_navigation and _player != null:
		_player.stop_navigation()


func _update_cursor_context() -> void:
	if not _using_pointer_aim or _player == null or not _player.control_enabled:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	var pointer := get_viewport().get_mouse_position()
	if (
		_battle_session() != null
		and _pointer_picker.enemy_at_screen(pointer, _enemy_views()) != null
	):
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	elif (
		_battle_session() == null
		and _pointer_picker.interactable_at_screen(pointer) != null
	):
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	elif screen_ground_point(pointer) == null:
		Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _navigation_rejected(result: PlayerCharacter3D.NavigationStartResult) -> bool:
	return result in [
		PlayerCharacter3D.NavigationStartResult.UNREACHABLE,
		PlayerCharacter3D.NavigationStartResult.NAVIGATION_UNAVAILABLE,
	]


func _show_navigation_failure(world_position: Vector3) -> void:
	_pointer_feedback.show_destination(
		world_position,
		PointerFeedback3D.DestinationKind.UNREACHABLE
	)
	_hud.show_notice(tr("UI_HUD_UNREACHABLE"))


func _target_ring_radius(enemy: EnemyActorView3D) -> float:
	return 1.65 if enemy.definition != null and enemy.definition.is_boss else 1.0


func _battle_session() -> BattleSession:
	return (
		_map_scene.current_battle_session()
		if _map_scene != null and is_instance_valid(_map_scene)
		else null
	)


func _enemy_views() -> Array[EnemyActorView3D]:
	return (
		_map_scene.enemy_views()
		if _map_scene != null and is_instance_valid(_map_scene)
		else []
	)


func _story_is_busy() -> bool:
	return (
		_map_scene.is_story_busy()
		if _map_scene != null and is_instance_valid(_map_scene)
		else false
	)
