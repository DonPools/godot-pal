class_name MapPointerPicker3D
extends RefCounted

const POINTER_TARGET_MASK := 1 << 4
const WORLD_COLLISION_MASK := 1 << 1
const POINTER_RAY_DISTANCE := 180.0

var _player: PlayerCharacter3D
var _camera: Camera3D


func configure(player: PlayerCharacter3D, camera: Camera3D) -> void:
	_player = player
	_camera = camera


func ground_point(screen_position: Vector2) -> Variant:
	var hit := _pointer_ray(screen_position, WORLD_COLLISION_MASK, false, true)
	return hit.get("position") if not hit.is_empty() else null


func screen_plane_fallback(screen_position: Vector2) -> Vector3:
	var ray_origin := _camera.project_ray_origin(screen_position)
	var ray_direction := _camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) <= 0.0001:
		return _player.global_position
	var distance := -ray_origin.y / ray_direction.y
	return (
		ray_origin + ray_direction * distance
		if distance > 0.0
		else _player.global_position
	)


func enemy_at_screen(
	screen_position: Vector2,
	enemy_views: Array[EnemyActorView3D]
) -> EnemyActorView3D:
	var collider := _pointer_collider(screen_position)
	if not collider is BattleHurtbox3D:
		return null
	var actor_id := (collider as BattleHurtbox3D).actor_id
	for enemy: EnemyActorView3D in enemy_views:
		if enemy.actor_id == actor_id and not enemy.is_defeated():
			return enemy
	return null


func interactable_at_screen(screen_position: Vector2) -> StoryInteractable3D:
	var collider := _pointer_collider(screen_position)
	if collider is StoryInteractable3D:
		var direct := collider as StoryInteractable3D
		return direct if direct.is_available() else null
	if collider is Node:
		var nested := (collider as Node).find_child("Interactable", true, false)
		if nested is StoryInteractable3D and (nested as StoryInteractable3D).is_available():
			return nested as StoryInteractable3D
	return null


func _pointer_collider(screen_position: Vector2) -> Object:
	var hit := _pointer_ray(
		screen_position,
		POINTER_TARGET_MASK | WORLD_COLLISION_MASK,
		true,
		true
	)
	return hit.get("collider") as Object if not hit.is_empty() else null


func _pointer_ray(
	screen_position: Vector2,
	collision_mask: int,
	collide_with_areas: bool,
	collide_with_bodies: bool
) -> Dictionary:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * POINTER_RAY_DISTANCE,
		collision_mask
	)
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = collide_with_bodies
	query.exclude = [_player.hurtbox.get_rid()]
	return _camera.get_world_3d().direct_space_state.intersect_ray(query)
