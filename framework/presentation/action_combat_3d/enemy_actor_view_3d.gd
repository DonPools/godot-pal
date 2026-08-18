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

var actor_id: StringName
var definition: EnemyDefinition
var state: State = State.DORMANT

var _map_scene: MapGameScene
var _player: PlayerCharacter3D
var _home_position := Vector3.ZERO
var _session: BattleSession
var _animation_player: AnimationPlayer
var _current_animation: StringName


func _ready() -> void:
	_animation_player = _find_animation_player(self)
	telegraph.visible = false
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
	state = State.DORMANT


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
	telegraph.visible = false
	_play_animation(&"idle")


func is_defeated() -> bool:
	return state == State.DEAD


func is_dormant_at_home() -> bool:
	return state == State.DORMANT and global_position.distance_to(_home_position) <= 0.3


func handle_battle_event(event: BattleEvent) -> void:
	if event.actor_id == actor_id:
		match event.kind:
			BattleEvent.Kind.ACTION_STARTED:
				telegraph.visible = true
				_play_animation(
					&"cast"
					if definition.combat_style == EnemyDefinition.CombatStyle.RANGED
					else &"attack"
				)
			BattleEvent.Kind.ACTION_ACTIVE:
				if definition.combat_style == EnemyDefinition.CombatStyle.MELEE:
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
				telegraph.visible = false
				_play_animation(&"idle")
			BattleEvent.Kind.DEATH:
				_die()
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
	velocity = Vector3.ZERO
	telegraph.visible = false
	collision_layer = 0
	collision_mask = 0
	_play_animation(&"death")


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
