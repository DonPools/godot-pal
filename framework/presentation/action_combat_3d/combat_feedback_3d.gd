class_name CombatFeedback3D
extends Node3D

const FLASH_SECONDS := 0.085
const SLASH_SECONDS := 0.18
const SPARK_SECONDS := 0.2
const AFTERIMAGE_SECONDS := 0.24

var _flash_tweens: Dictionary = {}
var _settings: SettingsService


func configure(settings: SettingsService) -> void:
	_settings = settings


func show_slash(origin: Vector3, direction: Vector3, empowered: bool = false) -> void:
	var flattened := Vector3(direction.x, 0.0, direction.z)
	if flattened.is_zero_approx():
		return
	var color := (
		Color(1.0, 0.76, 0.24, 0.9)
		if empowered
		else Color(0.72, 0.93, 1.0, 0.88)
	)
	var material := _effect_material(color)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
	for index: int in range(9):
		var ratio := float(index) / 8.0
		var angle := deg_to_rad(lerpf(-62.0, 62.0, ratio))
		for radius: float in [0.82, 1.28]:
			mesh.surface_add_vertex(
				Vector3(sin(angle) * radius, 0.0, -cos(angle) * radius)
			)
	mesh.surface_end()
	var effect := MeshInstance3D.new()
	effect.name = &"SwordArc"
	effect.mesh = mesh
	add_child(effect)
	effect.global_position = origin
	effect.look_at(origin + flattened.normalized(), Vector3.UP)
	effect.scale = Vector3(0.72, 0.72, 0.72)
	var tween := effect.create_tween()
	tween.set_parallel(true)
	tween.tween_property(effect, "scale", Vector3.ONE * 1.15, SLASH_SECONDS).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(effect, "transparency", 1.0, SLASH_SECONDS)
	tween.chain().tween_callback(effect.queue_free)


func show_hit_spark(position_3d: Vector3, player_was_hit: bool = false) -> void:
	var root := Node3D.new()
	root.name = &"HitSpark"
	add_child(root)
	root.global_position = position_3d
	root.scale = Vector3.ONE * 0.18
	var material := _effect_material(
		Color(1.0, 0.32, 0.18, 0.95)
		if player_was_hit
		else Color(1.0, 0.86, 0.34, 0.95)
	)
	var rays: Array[MeshInstance3D] = []
	for degrees: float in [0.0, 45.0, 90.0, 135.0]:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.055, 0.055, 0.78)
		mesh.material = material
		var ray := MeshInstance3D.new()
		ray.mesh = mesh
		ray.rotation_degrees = Vector3(0.0, degrees, 0.0)
		root.add_child(ray)
		rays.append(ray)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(root, "scale", Vector3.ONE, SPARK_SECONDS).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	for ray: MeshInstance3D in rays:
		tween.tween_property(ray, "transparency", 1.0, SPARK_SECONDS)
	tween.chain().tween_callback(root.queue_free)


func flash_actor(actor: Node3D, player_was_hit: bool = false) -> void:
	if (
		actor == null
		or not is_instance_valid(actor)
		or (_settings != null and _settings.reduce_combat_flashes)
	):
		return
	var actor_key := actor.get_instance_id()
	var previous := _flash_tweens.get(actor_key) as Tween
	if previous != null and previous.is_valid():
		previous.kill()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = (
		Color(1.0, 0.26, 0.18, 0.82)
		if player_was_hit
		else Color(1.0, 0.96, 0.72, 0.9)
	)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 2.6
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(actor, meshes)
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = material
	var tween := actor.create_tween()
	_flash_tweens[actor_key] = tween
	tween.tween_interval(FLASH_SECONDS)
	tween.tween_callback(func() -> void:
		for mesh: MeshInstance3D in meshes:
			if is_instance_valid(mesh) and mesh.material_overlay == material:
				mesh.material_overlay = null
		_flash_tweens.erase(actor_key)
	)


func show_dodge_afterimages(actor: Node3D, direction: Vector3) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var model := actor.get_node_or_null(^"Model") as Node3D
	if model == null:
		return
	var flattened := Vector3(direction.x, 0.0, direction.z)
	if flattened.is_zero_approx():
		flattened = Vector3.BACK
	flattened = flattened.normalized()
	for index: int in range(3):
		var ghost := model.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D
		if ghost == null:
			continue
		ghost.name = &"DodgeAfterimage"
		ghost.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(ghost)
		ghost.global_transform = model.global_transform
		ghost.global_position -= flattened * (0.22 + float(index) * 0.3)
		var ghost_material := _effect_material(
			Color(0.28, 0.88, 1.0, 0.34 - float(index) * 0.07)
		)
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(ghost, meshes)
		for mesh: MeshInstance3D in meshes:
			mesh.material_override = ghost_material
		var duration := AFTERIMAGE_SECONDS + float(index) * 0.04
		var tween := ghost.create_tween()
		tween.set_parallel(true)
		for mesh: MeshInstance3D in meshes:
			tween.tween_property(mesh, "transparency", 1.0, duration)
		tween.chain().tween_callback(ghost.queue_free)


func active_effect_count() -> int:
	return get_child_count()


func _effect_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 2.0
	return material


func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, result)
