class_name BattleProjectile3D
extends Area3D

var _map_scene: MapGameScene
var _actor_id: StringName
var _action_instance_id: int
var _direction := Vector3.FORWARD
var _speed: float = 8.0
var _remaining_seconds: float = 1.5
var _targets_player: bool = false
var _resolved: bool = false


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func configure(
	map_scene: MapGameScene,
	actor_id: StringName,
	action_instance_id: int,
	direction: Vector3,
	speed: float,
	targets_player: bool,
	lifetime_seconds: float
) -> void:
	_map_scene = map_scene
	_actor_id = actor_id
	_action_instance_id = action_instance_id
	_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	_speed = speed
	_targets_player = targets_player
	_remaining_seconds = lifetime_seconds
	if not _direction.is_zero_approx():
		look_at(global_position + _direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta
	_remaining_seconds -= delta
	if _remaining_seconds <= 0.0:
		_expire()


func _on_area_entered(area: Area3D) -> void:
	if _resolved or not area is BattleHurtbox3D:
		return
	var hurtbox := area as BattleHurtbox3D
	if _map_scene == null or _map_scene.battle_session == null:
		_expire()
		return
	var is_player := hurtbox.actor_id == _map_scene.battle_session.player.id
	if is_player != _targets_player:
		return
	_resolved = true
	_map_scene.resolve_battle_hit(_actor_id, _action_instance_id, hurtbox.actor_id)
	queue_free()


func _on_body_entered(_body: Node3D) -> void:
	_expire()


func _expire() -> void:
	if _resolved:
		return
	_resolved = true
	if _map_scene != null and _map_scene.battle_session != null:
		_map_scene.battle_session.expire_projectile_action(_action_instance_id)
	queue_free()
