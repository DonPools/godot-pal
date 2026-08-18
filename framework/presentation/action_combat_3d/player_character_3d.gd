class_name PlayerCharacter3D
extends CharacterBody3D

signal interact_requested
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

@onready var hurtbox: BattleHurtbox3D = $Hurtbox
@onready var melee_hitbox: Area3D = $MeleeHitbox
@onready var aim_marker: MeshInstance3D = $AimMarker

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


func _ready() -> void:
	_animation_player = _find_animation_player(self)
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
	_animation_player = _find_animation_player(model)
	_current_animation = &""
	_play_animation(&"idle")


func bind_map(map_scene: MapGameScene, camera: Camera3D) -> void:
	_map_scene = map_scene
	_camera = camera
	if map_scene.battle_session != null:
		hurtbox.configure(map_scene.battle_session.player.id)


func set_control_enabled(enabled: bool) -> void:
	control_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO


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


func aim_direction() -> Vector3:
	return _aim_direction


func movement_direction() -> Vector3:
	return _last_move_direction


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
	var input := Input.get_vector(&"move_west", &"move_east", &"move_north", &"move_south")
	var move_direction := _camera_space_direction(input)
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


func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled:
		return
	if _map_scene == null or not _map_scene.has_active_battle():
		if interaction_enabled and event.is_action_pressed(&"interact"):
			interact_requested.emit()
			get_viewport().set_input_as_handled()
		return
	var handled := true
	if event.is_action_pressed(&"combat_attack"):
		_map_scene.request_battle_action(BattleActionIntent.basic_attack(_battle_actor().id))
	elif event.is_action_pressed(&"combat_skill_one"):
		_request_skill(0)
	elif event.is_action_pressed(&"combat_skill_two"):
		_request_skill(1)
	elif event.is_action_pressed(&"combat_dodge"):
		_map_scene.request_battle_action(BattleActionIntent.dodge(_battle_actor().id))
	elif event.is_action_pressed(&"combat_item"):
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
		_map_scene.request_battle_action(BattleActionIntent.use_skill(_battle_actor().id, skill))


func _request_item() -> void:
	var inventory := _map_scene.scene_context.game_run.inventory
	for item_id: StringName in inventory.item_ids():
		var item := _map_scene.scene_context.content_database.item(item_id)
		if item != null and item.usable_in_battle and inventory.quantity(item_id) > 0:
			_map_scene.request_battle_action(
				BattleActionIntent.use_item(_battle_actor().id, item, _battle_actor().id)
			)
			return


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
			for candidate: Node in get_tree().get_nodes_in_group(&"battle_hurtboxes_3d"):
				if not candidate is BattleHurtbox3D or not is_ancestor_of(candidate):
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
