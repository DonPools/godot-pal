class_name MapCameraRig3D
extends Camera3D

const DEFAULT_OFFSET := Vector3(10.0, 10.0, 10.0)
const WORLD_COLLISION_MASK := 1 << 1

@export var follow_offset: Vector3 = DEFAULT_OFFSET

var _player: PlayerCharacter3D
var _interest_target_provider: Callable
var _focus := Vector3.ZERO
var _focus_initialized: bool = false
var _faded_obstacles: Dictionary = {}


func configure(
	player: PlayerCharacter3D,
	interest_target_provider: Callable = Callable()
) -> void:
	_player = player
	_interest_target_provider = interest_target_provider
	_focus_initialized = false


func _process(delta: float) -> void:
	_update_follow(delta)
	_update_occlusion()


func apply_obstacle_fade(desired: Dictionary) -> void:
	for obstacle: Node in _faded_obstacles.keys():
		if desired.has(obstacle) and is_instance_valid(obstacle):
			continue
		if is_instance_valid(obstacle):
			for mesh: MeshInstance3D in _faded_obstacles[obstacle]:
				if is_instance_valid(mesh):
					mesh.transparency = 0.0
		_faded_obstacles.erase(obstacle)
	for obstacle: Node in desired:
		if _faded_obstacles.has(obstacle):
			continue
		var meshes: Array[MeshInstance3D] = []
		_collect_mesh_instances(obstacle, meshes)
		for mesh: MeshInstance3D in meshes:
			mesh.transparency = 0.62
		_faded_obstacles[obstacle] = meshes


func restore_obstacles() -> void:
	apply_obstacle_fade({})


func refresh_immediately() -> void:
	_update_follow(0.0)
	_update_occlusion()


func focus_position() -> Vector3:
	return _focus


func _update_follow(delta: float) -> void:
	if _player == null:
		return
	var desired := _player.global_position + _player.aim_direction() * 1.8
	var interest_target := (
		_interest_target_provider.call() as Node3D
		if _interest_target_provider.is_valid()
		else null
	)
	if interest_target != null:
		var target_offset := interest_target.global_position - _player.global_position
		target_offset.y = 0.0
		if not target_offset.is_zero_approx():
			desired = _player.global_position + target_offset.normalized() * minf(
				target_offset.length() * 0.6,
				3.2
			)
	if not _focus_initialized or delta <= 0.0:
		_focus = desired
		_focus_initialized = true
	else:
		_focus = _focus.lerp(desired, 1.0 - exp(-8.0 * delta))
	global_position = _focus + follow_offset
	look_at(_focus, Vector3.UP)


func _update_occlusion() -> void:
	if _player == null or _player.hurtbox == null:
		return
	var desired: Dictionary = {}
	var excluded: Array[RID] = [_player.hurtbox.get_rid()]
	var target := _player.global_position + Vector3.UP * 0.95
	for _hit_index: int in range(4):
		var query := PhysicsRayQueryParameters3D.create(
			global_position,
			target,
			WORLD_COLLISION_MASK
		)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = excluded
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var collider := hit.get("collider") as CollisionObject3D
		if collider == null or not collider.is_in_group(&"camera_fade_obstacle"):
			break
		desired[collider] = true
		excluded.append(collider.get_rid())
	apply_obstacle_fade(desired)


func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_mesh_instances(child, result)
