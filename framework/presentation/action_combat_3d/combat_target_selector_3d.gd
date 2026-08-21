class_name CombatTargetSelector3D
extends RefCounted

const TARGET_COLLISION_MASK := 1 << 4
const WORLD_COLLISION_MASK := 1 << 1
const ACQUIRE_DISTANCE := 8.0
const RETAIN_DISTANCE := 10.0
const ACQUIRE_ANGLE_DEGREES := 50.0
const RETAIN_ANGLE_DEGREES := 65.0
const ANGLE_SCORE_WEIGHT := 2.2

var _player: PlayerCharacter3D
var _camera: Camera3D
var _target: EnemyActorView3D


func configure(player: PlayerCharacter3D, camera: Camera3D) -> void:
	_player = player
	_camera = camera


func clear() -> void:
	_target = null


func current_target() -> EnemyActorView3D:
	return _target


func acquire_direction(
	enemy_views: Array[EnemyActorView3D],
	battle_active: bool
) -> Vector3:
	if not battle_active or _player == null or _camera == null:
		clear()
		return Vector3.ZERO
	if _is_valid(_target, RETAIN_DISTANCE, RETAIN_ANGLE_DEGREES):
		return _target.global_position - _player.global_position
	clear()
	var best_score := INF
	for enemy_view: EnemyActorView3D in enemy_views:
		if not _is_valid(enemy_view, ACQUIRE_DISTANCE, ACQUIRE_ANGLE_DEGREES):
			continue
		var direction := enemy_view.global_position - _player.global_position
		direction.y = 0.0
		var angle := _player.aim_direction().angle_to(direction.normalized())
		var score := direction.length() + angle * ANGLE_SCORE_WEIGHT
		if score < best_score:
			_target = enemy_view
			best_score = score
	return (
		_target.global_position - _player.global_position
		if _target != null
		else Vector3.ZERO
	)


func cycle(enemy_views: Array[EnemyActorView3D]) -> EnemyActorView3D:
	if _player == null or _camera == null:
		clear()
		return null
	var candidates: Array[EnemyActorView3D] = []
	for enemy_view: EnemyActorView3D in enemy_views:
		if _is_visible(enemy_view, RETAIN_DISTANCE):
			candidates.append(enemy_view)
	if candidates.is_empty():
		clear()
		return null
	candidates.sort_custom(func(left: EnemyActorView3D, right: EnemyActorView3D) -> bool:
		return _camera.unproject_position(left.global_position).x < _camera.unproject_position(
			right.global_position
		).x
	)
	var current_index := candidates.find(_target)
	_target = candidates[(current_index + 1) % candidates.size()]
	return _target


func _is_valid(
	enemy: EnemyActorView3D,
	max_distance: float,
	max_angle_degrees: float
) -> bool:
	if not _is_visible(enemy, max_distance):
		return false
	var direction := enemy.global_position - _player.global_position
	direction.y = 0.0
	return (
		not direction.is_zero_approx()
		and rad_to_deg(_player.aim_direction().angle_to(direction.normalized()))
		<= max_angle_degrees
	)


func _is_visible(enemy: EnemyActorView3D, max_distance: float) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_defeated():
		return false
	var target_position := enemy.global_position + Vector3.UP * 0.85
	if _player.global_position.distance_to(enemy.global_position) > max_distance:
		return false
	if _camera.is_position_behind(target_position):
		return false
	var viewport := _camera.get_viewport()
	if viewport == null or not viewport.get_visible_rect().has_point(
		_camera.unproject_position(target_position)
	):
		return false
	var query := PhysicsRayQueryParameters3D.create(
		_camera.global_position,
		target_position,
		TARGET_COLLISION_MASK | WORLD_COLLISION_MASK
	)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [_player.hurtbox.get_rid()]
	var world := _camera.get_world_3d()
	if world == null:
		return false
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.get("collider") as Node
	return collider == enemy.hurtbox or (collider != null and enemy.is_ancestor_of(collider))
