class_name PlayerCharacter3D
extends CharacterBody3D

signal interact_requested
signal pointer_intent_cancelled
signal navigation_failed(target: Vector3, reason: NavigationFailure)
signal projectile_requested(
	actor_id: StringName,
	action_instance_id: int,
	origin: Vector3,
	direction: Vector3
)
signal damage_number_requested(position_3d: Vector3, amount: int, enemy_damage: bool)

const MOVE_ACCELERATION := 30.0
const MOVE_DECELERATION := 60.0
const DODGE_SPEED := 10.5
const EXPLORATION_SPEED := 8.0
const INPUT_BUFFER_SECONDS := 0.22
const NAVIGATION_REPATH_DISTANCE := 0.2
const NAVIGATION_SNAP_LIMIT := 3.0
const NAVIGATION_STALL_SECONDS := 0.9
const NAVIGATION_PROGRESS_EPSILON := 0.035

enum NavigationStartResult {
	STARTED,
	ALREADY_THERE,
	UNREACHABLE,
	NAVIGATION_UNAVAILABLE,
}

enum NavigationFailure {
	PATH_ENDED,
	STALLED,
}

@onready var hurtbox: BattleHurtbox3D = $Hurtbox
@onready var melee_hitbox: Area3D = $MeleeHitbox
@onready var aim_marker: MeshInstance3D = $AimMarker
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

var control_enabled: bool = true
var interaction_enabled: bool = true
var direction: StringName = &"south"

var _definition: ActorDefinition
var _map_scene: MapGameScene
var _camera: Camera3D
var _aim_direction := Vector3(0.0, 0.0, -1.0)
var _last_move_direction := Vector3(0.0, 0.0, -1.0)
var _dodge_direction := Vector3.ZERO
var _dodging: bool = false
var _animation_player: AnimationPlayer
var _current_animation: StringName
var _cultivation_aura: OmniLight3D
var _navigating: bool = false
var _navigation_target := Vector3.ZERO
var _navigation_stopping_distance: float = 0.2
var _navigation_last_distance: float = INF
var _navigation_stall_elapsed: float = 0.0
var _direct_input_active: bool = false
var _movement_deadzone: float = SettingsService.DEFAULT_MOVEMENT_DEADZONE
var _buffered_intent: BattleActionIntent
var _buffer_remaining: float = 0.0


func _ready() -> void:
	add_to_group(&"battle_motion_3d")
	_animation_player = _find_animation_player(self)
	navigation_agent.path_desired_distance = 0.2
	navigation_agent.target_desired_distance = _navigation_stopping_distance
	hurtbox.set_pointer_enabled(false)
	aim_marker.visible = false
	_play_animation(&"idle")


func configure(definition: ActorDefinition) -> void:
	_definition = definition
	if definition == null:
		push_error("PlayerCharacter3D requires an ActorDefinition")
		return
	if definition.field_model_3d == null:
		push_error("PlayerCharacter3D requires ActorDefinition.field_model_3d")
		return
	var previous_model := get_node_or_null(^"Model") as Node3D
	if previous_model != null:
		remove_child(previous_model)
		previous_model.free()
	var model := definition.field_model_3d.instantiate() as Node3D
	if model == null:
		push_error("ActorDefinition field_model_3d root must be Node3D")
		return
	model.name = &"Model"
	add_child(model)
	move_child(model, 0)
	ModelPresentation3D.apply_outline(model, 0.02)
	_animation_player = _find_animation_player(model)
	_current_animation = &""
	_play_animation(&"idle")


func bind_map(map_scene: MapGameScene, camera: Camera3D) -> void:
	_map_scene = map_scene
	_camera = camera
	if map_scene.battle_session != null:
		hurtbox.configure(map_scene.battle_session.player.id)


func configure_input_tuning(movement_deadzone: float) -> void:
	_movement_deadzone = clampf(
		movement_deadzone,
		SettingsService.MIN_STICK_DEADZONE,
		SettingsService.MAX_STICK_DEADZONE
	)


func set_cultivation_aura(color: Color, enabled: bool) -> void:
	if _cultivation_aura == null:
		_cultivation_aura = OmniLight3D.new()
		_cultivation_aura.name = &"CultivationAura"
		_cultivation_aura.position = Vector3(0, 1.0, 0)
		_cultivation_aura.omni_range = 3.5
		add_child(_cultivation_aura)
	_cultivation_aura.light_color = color
	_cultivation_aura.light_energy = 1.15 if enabled else 0.0


func set_aim_marker_visible(enabled: bool) -> void:
	aim_marker.visible = enabled


func set_control_enabled(enabled: bool) -> void:
	control_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO
		stop_navigation()
		_clear_action_buffer()


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled


func set_direction(value: StringName) -> void:
	direction = value
	match value:
		&"north":
			set_aim_direction(Vector3.FORWARD)
		&"south":
			set_aim_direction(Vector3.BACK)
		&"west":
			set_aim_direction(Vector3.LEFT)
		&"east":
			set_aim_direction(Vector3.RIGHT)


func set_aim_direction(value: Vector3) -> void:
	var flattened := Vector3(value.x, 0.0, value.z)
	if flattened.length_squared() <= 0.001:
		return
	_aim_direction = flattened.normalized()
	_face(_aim_direction)
	aim_marker.global_position = global_position + _aim_direction * 0.85 + Vector3.UP * 0.04
	aim_marker.look_at(aim_marker.global_position + _aim_direction, Vector3.UP)


func turn_aim_toward(value: Vector3, weight: float) -> void:
	var flattened := Vector3(value.x, 0.0, value.z)
	if flattened.length_squared() <= 0.001:
		return
	var target := flattened.normalized()
	set_aim_direction(_aim_direction.slerp(target, clampf(weight, 0.0, 1.0)))


func aim_direction() -> Vector3:
	return _aim_direction


func movement_direction() -> Vector3:
	return _last_move_direction


func navigate_to(
	target: Vector3,
	stopping_distance: float = 0.2
) -> NavigationStartResult:
	var navigation_map := navigation_agent.get_navigation_map()
	if not navigation_map.is_valid():
		return NavigationStartResult.NAVIGATION_UNAVAILABLE
	var snapped := NavigationServer3D.map_get_closest_point(navigation_map, target)
	if snapped.distance_to(target) > NAVIGATION_SNAP_LIMIT:
		return NavigationStartResult.UNREACHABLE
	var flattened := Vector3(snapped.x, global_position.y, snapped.z)
	if global_position.distance_to(flattened) <= stopping_distance:
		stop_navigation()
		return NavigationStartResult.ALREADY_THERE
	var distance_changed := absf(stopping_distance - _navigation_stopping_distance) > 0.01
	if (
		not _navigating
		or flattened.distance_to(_navigation_target) > NAVIGATION_REPATH_DISTANCE
		or distance_changed
	):
		var path := NavigationServer3D.map_get_path(
			navigation_map,
			global_position,
			snapped,
			true,
			navigation_agent.navigation_layers
		)
		if path.is_empty():
			return NavigationStartResult.UNREACHABLE
		_navigation_target = flattened
		_navigation_stopping_distance = maxf(stopping_distance, 0.05)
		navigation_agent.target_desired_distance = _navigation_stopping_distance
		navigation_agent.target_position = snapped
		_navigation_last_distance = global_position.distance_to(_navigation_target)
		_navigation_stall_elapsed = 0.0
	_navigating = true
	return NavigationStartResult.STARTED


func stop_navigation() -> void:
	_navigating = false
	_navigation_target = global_position
	_navigation_last_distance = INF
	_navigation_stall_elapsed = 0.0
	if navigation_agent != null:
		navigation_agent.target_position = global_position


func is_navigating() -> bool:
	return _navigating


func navigation_target_position() -> Vector3:
	return _navigation_target


func handle_battle_event(event: BattleEvent) -> void:
	if _map_scene == null or _map_scene.battle_session == null:
		return
	var player_id := _map_scene.battle_session.player.id
	if event.actor_id == player_id:
		match event.kind:
			BattleEvent.Kind.ACTION_STARTED:
				_play_animation(&"attack" if event.action_id == BattleSession.BASIC_ATTACK_ID else &"cast")
			BattleEvent.Kind.ACTION_ACTIVE:
				_resolve_active_action(event)
			BattleEvent.Kind.PROJECTILE_REQUESTED:
				projectile_requested.emit(
					event.actor_id,
					event.action_instance_id,
					global_position + Vector3.UP * 0.85 + _aim_direction * 0.65,
					_aim_direction
				)
			BattleEvent.Kind.DODGE_STARTED:
				_dodging = true
				_dodge_direction = (
					_last_move_direction
					if not _last_move_direction.is_zero_approx()
					else _aim_direction
				)
			BattleEvent.Kind.ACTION_FINISHED:
				_dodging = false
				_play_animation(&"idle")
			BattleEvent.Kind.DEATH:
				_play_animation(&"death")
	if event.target_id == player_id or (
		event.actor_id == player_id
		and event.kind == BattleEvent.Kind.STATUS_TICK
	):
		if event.kind in [BattleEvent.Kind.DAMAGE, BattleEvent.Kind.STATUS_TICK]:
			_play_animation(&"hit")
			damage_number_requested.emit(
				global_position + Vector3.UP * 1.8,
				event.amount,
				false
			)


func _physics_process(delta: float) -> void:
	_advance_action_buffer(delta)
	if not control_enabled:
		velocity = Vector3.ZERO
		return
	if _dodging:
		velocity = _dodge_direction * DODGE_SPEED
		move_and_slide()
		return
	var actor := _battle_actor()
	if actor != null and actor.current_action != null:
		velocity = Vector3.ZERO
		return
	var input := Input.get_vector(
		&"move_west", &"move_east", &"move_north", &"move_south", _movement_deadzone
	)
	var move_direction := Vector3.ZERO
	if not input.is_zero_approx():
		if not _direct_input_active:
			_direct_input_active = true
			stop_navigation()
			pointer_intent_cancelled.emit()
		move_direction = _camera_space_direction(input)
	else:
		_direct_input_active = false
		move_direction = _navigation_direction()
	if move_direction.is_zero_approx():
		velocity = velocity.move_toward(Vector3.ZERO, MOVE_DECELERATION * delta)
		if velocity.is_zero_approx():
			_play_animation(&"idle")
	else:
		_last_move_direction = move_direction
		velocity = velocity.move_toward(move_direction * _move_speed(), MOVE_ACCELERATION * delta)
		_play_animation(&"run")
		if actor == null:
			set_aim_direction(move_direction)
	move_and_slide()
	_update_navigation_progress(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled:
		return
	if event is InputEventMouseButton and event.is_action(&"combat_attack"):
		return
	if _map_scene == null or not _map_scene.has_active_battle():
		if interaction_enabled and event.is_action_pressed(&"interact"):
			_cancel_pointer_control()
			interact_requested.emit()
			get_viewport().set_input_as_handled()
		return
	var handled := true
	if event.is_action_pressed(&"combat_attack"):
		_cancel_pointer_control()
		_request_player_action(BattleActionIntent.basic_attack(_battle_actor().id))
	elif event.is_action_pressed(&"combat_skill_one"):
		_cancel_pointer_control()
		_request_skill(0)
	elif event.is_action_pressed(&"combat_skill_two"):
		_cancel_pointer_control()
		_request_skill(1)
	elif event.is_action_pressed(&"combat_skill_three"):
		_cancel_pointer_control()
		_request_skill(2)
	elif event.is_action_pressed(&"combat_dodge"):
		_cancel_pointer_control()
		_request_player_action(BattleActionIntent.dodge(_battle_actor().id))
	elif event.is_action_pressed(&"combat_item"):
		_cancel_pointer_control()
		_request_item()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _request_skill(index: int) -> void:
	var actor_state := _map_scene.scene_context.game_run.party.leader()
	if actor_state == null or index >= actor_state.skill_ids.size():
		return
	var skill := _map_scene.scene_context.content_database.skill(actor_state.skill_ids[index])
	if skill != null:
		_request_player_action(BattleActionIntent.use_skill(_battle_actor().id, skill))


func _request_item() -> void:
	var inventory := _map_scene.scene_context.game_run.inventory
	for item_id: StringName in inventory.item_ids():
		var item := _map_scene.scene_context.content_database.item(item_id)
		if item != null and item.usable_in_battle and inventory.quantity(item_id) > 0:
			_request_player_action(
				BattleActionIntent.use_item(_battle_actor().id, item, _battle_actor().id)
			)
			return
	if _map_scene is MapGameScene3D:
		(_map_scene as MapGameScene3D).show_action_rejection(
			BattleActionRequestResult.Rejection.ITEM_UNAVAILABLE
		)


func _request_player_action(intent: BattleActionIntent) -> BattleActionRequestResult:
	var result := _map_scene.request_battle_action(intent)
	if result.rejection == BattleActionRequestResult.Rejection.ACTOR_BUSY:
		_buffered_intent = intent
		_buffer_remaining = INPUT_BUFFER_SECONDS
	else:
		_clear_action_buffer()
	return result


func _advance_action_buffer(delta: float) -> void:
	if _buffered_intent == null:
		return
	_buffer_remaining = maxf(_buffer_remaining - delta, 0.0)
	var actor := _battle_actor()
	if _buffer_remaining <= 0.0 or actor == null:
		_clear_action_buffer()
		return
	if not actor.can_act():
		return
	var result := _map_scene.request_battle_action(_buffered_intent)
	if result.rejection != BattleActionRequestResult.Rejection.ACTOR_BUSY:
		_clear_action_buffer()


func _clear_action_buffer() -> void:
	_buffered_intent = null
	_buffer_remaining = 0.0


func _cancel_pointer_control() -> void:
	stop_navigation()
	pointer_intent_cancelled.emit()


func _resolve_active_action(event: BattleEvent) -> void:
	var action := _battle_actor().current_action
	if action == null:
		return
	if event.action_id == BattleSession.BASIC_ATTACK_ID:
		melee_hitbox.global_position = global_position + _aim_direction * 1.05 + Vector3.UP
		for area: Area3D in melee_hitbox.get_overlapping_areas():
			if area is BattleHurtbox3D:
				var target_id := (area as BattleHurtbox3D).actor_id
				if target_id != _battle_actor().id:
					_map_scene.resolve_battle_hit(_battle_actor().id, event.action_instance_id, target_id)
	elif action.intent.kind == BattleActionIntent.Kind.SKILL and action.intent.skill != null:
		if action.intent.skill.target_rule == SkillDefinition.TargetRule.AREA:
			if _map_scene is MapGameScene3D:
				(_map_scene as MapGameScene3D).show_area_skill_effect(
					global_position,
					action.intent.skill.radius,
					Color(1.0, 0.78, 0.3, 0.72)
					if &"ultimate" in action.intent.skill.tags
					else Color(0.35, 0.82, 1.0, 0.58)
				)
			for candidate: Node in get_tree().get_nodes_in_group(&"battle_hurtboxes_3d"):
				if (
					not candidate is BattleHurtbox3D
					or _map_scene == null
					or not _map_scene.is_ancestor_of(candidate)
				):
					continue
				var target_hurtbox := candidate as BattleHurtbox3D
				if (
					target_hurtbox.actor_id != _battle_actor().id
					and global_position.distance_to(target_hurtbox.global_position)
					<= action.intent.skill.radius
				):
					_map_scene.resolve_battle_hit(
						_battle_actor().id,
						event.action_instance_id,
						target_hurtbox.actor_id
					)
	elif action.intent.kind == BattleActionIntent.Kind.ITEM:
		_map_scene.resolve_battle_hit(
			_battle_actor().id,
			event.action_instance_id,
			_battle_actor().id
		)


func _battle_actor() -> BattleActorState:
	return (
		_map_scene.battle_session.player
		if _map_scene != null and _map_scene.battle_session != null
		else null
	)


func _move_speed() -> float:
	var actor := _battle_actor()
	return actor.move_speed if actor != null else EXPLORATION_SPEED


func _navigation_direction() -> Vector3:
	if not _navigating:
		return Vector3.ZERO
	if navigation_agent.is_navigation_finished():
		var target := _navigation_target
		var reached := global_position.distance_to(target) <= _navigation_stopping_distance + 0.15
		stop_navigation()
		if not reached:
			navigation_failed.emit(target, NavigationFailure.PATH_ENDED)
		return Vector3.ZERO
	var next_position := navigation_agent.get_next_path_position()
	var direction := next_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0025:
		return Vector3.ZERO
	return direction.normalized()


func _update_navigation_progress(delta: float) -> void:
	if not _navigating:
		return
	var distance := global_position.distance_to(_navigation_target)
	if _navigation_last_distance - distance >= NAVIGATION_PROGRESS_EPSILON:
		_navigation_stall_elapsed = 0.0
	else:
		_navigation_stall_elapsed += delta
	_navigation_last_distance = distance
	if _navigation_stall_elapsed < NAVIGATION_STALL_SECONDS:
		return
	var target := _navigation_target
	stop_navigation()
	navigation_failed.emit(target, NavigationFailure.STALLED)


func _camera_space_direction(input: Vector2) -> Vector3:
	if input.is_zero_approx() or _camera == null:
		return Vector3.ZERO
	var right := _camera.global_basis.x
	right.y = 0.0
	var forward := -_camera.global_basis.z
	forward.y = 0.0
	return (right.normalized() * input.x + forward.normalized() * -input.y).normalized()


func _face(value: Vector3) -> void:
	var model := get_node_or_null(^"Model") as Node3D
	if model != null and not value.is_zero_approx():
		model.look_at(model.global_position + value, Vector3.UP)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _play_animation(short_name: StringName) -> void:
	if _animation_player == null or _current_animation == short_name:
		return
	for candidate: StringName in _animation_player.get_animation_list():
		if String(candidate).get_slice("/", -1) == String(short_name):
			_animation_player.play(candidate)
			_current_animation = short_name
			return
