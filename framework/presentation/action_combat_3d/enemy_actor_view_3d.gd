class_name EnemyActorView3D
extends CharacterBody3D

signal alert_requested
signal returned_home
signal projectile_requested(
	actor_id: StringName,
	action_instance_id: int,
	origin: Vector3,
	direction: Vector3,
	speed: float
)
signal damage_number_requested(position_3d: Vector3, amount: int, enemy_damage: bool)

enum State {
	DORMANT,
	ACTIVE,
	RETURNING,
	DEAD,
}

@onready var hurtbox: BattleHurtbox3D = $Hurtbox
@onready var telegraph: MeshInstance3D = $Telegraph
@onready var stagger_label: Label3D = get_node_or_null(^"StaggerLabel") as Label3D

var actor_id: StringName
var definition: EnemyDefinition
var state: State = State.DORMANT

var _map_scene: MapGameScene
var _player: PlayerCharacter3D
var _home_position := Vector3.ZERO
var _session: BattleSession
var _animation_player: AnimationPlayer
var _current_animation: StringName
var _charging: bool = false
var _charge_direction := Vector3.ZERO
var _charge_action_instance_id: int = 0
var _telegraph_rest_transform := Transform3D.IDENTITY
var _telegraph_tween: Tween


func _ready() -> void:
	add_to_group(&"battle_motion_3d")
	_animation_player = _find_animation_player(self)
	ModelPresentation3D.apply_outline(get_node_or_null(^"Model"), 0.026)
	_telegraph_rest_transform = telegraph.transform
	telegraph.visible = false
	_set_stagger_visual(false)
	_play_animation(&"idle")


func configure_dormant(
	map_scene: MapGameScene,
	player: PlayerCharacter3D,
	entry: EncounterEnemy
) -> void:
	_map_scene = map_scene
	_player = player
	actor_id = entry.instance_id
	definition = entry.enemy
	_home_position = global_position
	hurtbox.configure(actor_id)
	hurtbox.set_pointer_enabled(true)
	state = State.DORMANT
	_charging = false
	_set_stagger_visual(false)


func begin_session(session: BattleSession) -> void:
	_session = session
	state = State.ACTIVE
	telegraph.visible = false


func reset_dormant() -> void:
	_session = null
	global_position = _home_position
	velocity = Vector3.ZERO
	visible = true
	collision_layer = 4
	collision_mask = 3
	state = State.DORMANT
	hurtbox.set_pointer_enabled(true)
	telegraph.visible = false
	telegraph.transform = _telegraph_rest_transform
	_set_stagger_visual(false)
	_play_animation(&"idle")


func is_defeated() -> bool:
	return state == State.DEAD


func is_dormant_at_home() -> bool:
	return state == State.DORMANT and global_position.distance_to(_home_position) <= 0.3


func handle_battle_event(event: BattleEvent) -> void:
	if event.actor_id == actor_id:
		match event.kind:
			BattleEvent.Kind.ACTION_STARTED:
				_start_attack_telegraph(event.action_id)
				_play_animation(
					&"cast"
					if definition.combat_style == EnemyDefinition.CombatStyle.RANGED
					else &"attack"
				)
				if event.action_id == BattleSession.CHARGE_ID:
					_charge_direction = _player.global_position - global_position
					_charge_direction.y = 0.0
					_charge_direction = _charge_direction.normalized()
					_charge_action_instance_id = event.action_instance_id
					_position_charge_telegraph()
			BattleEvent.Kind.ACTION_ACTIVE:
				_finish_attack_telegraph()
				if event.action_id == BattleSession.CHARGE_ID:
					_charging = true
				elif definition.combat_style in [
					EnemyDefinition.CombatStyle.MELEE,
					EnemyDefinition.CombatStyle.CHARGER,
				]:
					_resolve_melee(event.action_instance_id)
			BattleEvent.Kind.PROJECTILE_REQUESTED:
				var direction: Vector3 = _player.global_position - global_position
				direction.y = 0.0
				projectile_requested.emit(
					actor_id,
					event.action_instance_id,
					global_position + Vector3.UP * 0.9 + direction.normalized() * 0.65,
					direction,
					definition.projectile_speed
				)
			BattleEvent.Kind.ACTION_FINISHED:
				_charging = false
				telegraph.visible = false
				_play_animation(&"idle")
			BattleEvent.Kind.DEATH:
				_die()
			BattleEvent.Kind.STAGGER_STARTED:
				_charging = false
				velocity = Vector3.ZERO
				telegraph.visible = false
				_set_stagger_visual(true)
				_play_animation(&"hit")
			BattleEvent.Kind.STAGGER_ENDED:
				_set_stagger_visual(false)
				_play_animation(&"idle")
	if event.target_id == actor_id or (
		event.actor_id == actor_id and event.kind == BattleEvent.Kind.STATUS_TICK
	):
		if event.kind in [BattleEvent.Kind.DAMAGE, BattleEvent.Kind.STATUS_TICK]:
			_play_animation(&"hit")
			damage_number_requested.emit(
				global_position + Vector3.UP * 1.8,
				event.amount,
				true
			)


func _physics_process(_delta: float) -> void:
	if _map_scene == null or state == State.DEAD:
		velocity = Vector3.ZERO
		return
	if state == State.DORMANT:
		if global_position.distance_to(_player.global_position) <= definition.aggro_range:
			alert_requested.emit()
		return
	if state == State.RETURNING:
		_return_home()
		return
	if _session == null or _session.finished:
		return
	var actor := _session.actor(actor_id)
	if actor == null or not actor.is_alive():
		return
	if actor.stagger_remaining_seconds > 0.0:
		velocity = Vector3.ZERO
		return
	if _charging:
		_advance_charge(actor)
		return
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if (
		global_position.distance_to(_home_position) > definition.leash_radius
		or to_player.length() > definition.leash_radius * 1.35
	):
		state = State.RETURNING
		telegraph.visible = false
		return
	if actor.current_action != null:
		velocity = Vector3.ZERO
		return
	var distance: float = to_player.length()
	if distance <= 0.001:
		return
	var direction: Vector3 = to_player.normalized()
	_face(direction)
	if (
		definition.combat_style == EnemyDefinition.CombatStyle.CHARGER
		and distance >= 2.0
		and distance <= definition.aggro_range
		and actor.cooldown_remaining(BattleSession.CHARGE_ID) <= 0.0
	):
		velocity = Vector3.ZERO
		_map_scene.request_battle_action(
			BattleActionIntent.charge(actor_id, _session.player.id)
		)
		return
	if distance <= definition.attack_range:
		velocity = Vector3.ZERO
		_map_scene.request_battle_action(
			BattleActionIntent.basic_attack(actor_id, _session.player.id)
		)
		return
	if (
		definition.combat_style == EnemyDefinition.CombatStyle.RANGED
		and distance < definition.attack_range * 0.55
	):
		direction = -direction
	velocity = direction * definition.move_speed
	_play_animation(&"run")
	move_and_slide()


func _resolve_melee(action_instance_id: int) -> void:
	if (
		_player.global_position.distance_to(global_position)
		<= definition.attack_range + 0.45
	):
		_map_scene.resolve_battle_hit(actor_id, action_instance_id, _session.player.id)


func _advance_charge(actor: BattleActorState) -> void:
	if _charge_direction.is_zero_approx():
		return
	_face(_charge_direction)
	velocity = _charge_direction * actor.charge_speed
	_play_animation(&"run")
	move_and_slide()
	if global_position.distance_to(_player.global_position) <= 1.15:
		_map_scene.resolve_battle_hit(
			actor_id,
			_charge_action_instance_id,
			_session.player.id
		)
	for index: int in range(get_slide_collision_count()):
		var collider := get_slide_collision(index).get_collider() as Node
		if collider != null and collider.is_in_group(&"battle_array_pillars"):
			var pillar_id := StringName(collider.get_meta(&"pillar_id", ""))
			_map_scene.resolve_battle_pillar_contact(
				actor_id,
				_charge_action_instance_id,
				pillar_id
			)
			return


func _return_home() -> void:
	var direction := _home_position - global_position
	direction.y = 0.0
	if direction.length() <= 0.25:
		global_position = _home_position
		velocity = Vector3.ZERO
		state = State.DORMANT
		_session = null
		_play_animation(&"idle")
		returned_home.emit()
		return
	_face(direction.normalized())
	velocity = direction.normalized() * definition.move_speed * 1.15
	_play_animation(&"run")
	move_and_slide()


func _die() -> void:
	state = State.DEAD
	_charging = false
	velocity = Vector3.ZERO
	telegraph.visible = false
	_set_stagger_visual(false)
	collision_layer = 0
	collision_mask = 0
	hurtbox.set_pointer_enabled(false)
	_play_animation(&"death")


func _start_attack_telegraph(action_id: StringName) -> void:
	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	telegraph.transform = _telegraph_rest_transform
	telegraph.transparency = 0.18
	telegraph.visible = true
	var target_scale := _telegraph_rest_transform.basis.get_scale()
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	if action_id == BattleSession.CHARGE_ID:
		_position_charge_telegraph()
		target_scale = telegraph.scale
	elif not to_player.is_zero_approx():
		var direction := to_player.normalized()
		if definition.combat_style == EnemyDefinition.CombatStyle.RANGED:
			var distance := minf(to_player.length(), definition.attack_range)
			telegraph.global_position = (
				global_position + direction * distance * 0.5 + Vector3.UP * 0.045
			)
			telegraph.look_at(telegraph.global_position + direction, Vector3.UP)
			target_scale = Vector3(0.24, 1.0, maxf(distance / 1.7, 1.0))
		else:
			telegraph.global_position = global_position + direction * 0.9 + Vector3.UP * 0.045
			target_scale = Vector3.ONE * maxf(definition.attack_range / 1.7, 0.8)
	telegraph.scale = target_scale * 0.58
	var windup := 0.28
	if _session != null:
		var actor := _session.actor(actor_id)
		if actor != null and actor.current_action != null:
			windup = maxf(actor.current_action.windup_seconds, 0.12)
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	_telegraph_tween.tween_property(telegraph, "scale", target_scale, windup).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	_telegraph_tween.tween_property(telegraph, "transparency", 0.0, windup)


func _finish_attack_telegraph() -> void:
	if not telegraph.visible:
		return
	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	var active_scale := telegraph.scale
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	_telegraph_tween.tween_property(
		telegraph, "scale", active_scale * 1.08, 0.08
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_telegraph_tween.tween_property(telegraph, "transparency", 0.42, 0.08)


func _set_stagger_visual(enabled: bool) -> void:
	if stagger_label != null:
		stagger_label.visible = enabled
	var model := get_node_or_null(^"Model") as Node3D
	if model != null:
		model.rotation_degrees.z = 7.0 if enabled else 0.0


func _position_charge_telegraph() -> void:
	if _charge_direction.is_zero_approx():
		return
	telegraph.global_position = global_position + _charge_direction * 3.6 + Vector3.UP * 0.05
	telegraph.look_at(telegraph.global_position + _charge_direction, Vector3.UP)


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
