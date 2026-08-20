class_name Original3DAssetValidator
extends RefCounted

const MANIFEST_PATH := "res://assets/original/3d/manifest.json"
const REQUIRED_ANIMATIONS: Array[StringName] = [
	&"idle", &"run", &"attack", &"cast", &"hit", &"death",
]
const REQUIRED_BONES: PackedStringArray = [
	"hips", "spine", "head", "upper_arm_l", "lower_arm_l",
	"upper_arm_r", "lower_arm_r", "upper_leg_l", "lower_leg_l",
	"foot_l", "upper_leg_r", "lower_leg_r", "foot_r",
]
const CHARACTER_MODELS: PackedStringArray = [
	"res://assets/original/3d/models/humanoid_base.glb",
	"res://assets/original/3d/models/humanoid_variant.glb",
	"res://assets/original/3d/models/mountain_raider.glb",
]
const CHARACTER_SCENES: PackedStringArray = [
	"res://game/presentation/action_combat_3d/characters/humanoid_base_character.tscn",
	"res://game/presentation/action_combat_3d/characters/humanoid_variant_character.tscn",
	"res://game/presentation/action_combat_3d/characters/mountain_raider_character.tscn",
]
const ENVIRONMENT_SCENES: PackedStringArray = [
	"res://game/presentation/action_combat_3d/environment/ground_grass.tscn",
	"res://game/presentation/action_combat_3d/environment/road_stone.tscn",
	"res://game/presentation/action_combat_3d/environment/rocks_cluster.tscn",
	"res://game/presentation/action_combat_3d/environment/pine_tree.tscn",
	"res://game/presentation/action_combat_3d/environment/pine_tree_young.tscn",
	"res://game/presentation/action_combat_3d/environment/mountain_shrub.tscn",
	"res://game/presentation/action_combat_3d/environment/wood_fence.tscn",
	"res://game/presentation/action_combat_3d/environment/roadside_hut.tscn",
]
const PLANT_MODELS: PackedStringArray = [
	"res://assets/original/3d/models/fanqing_grass.glb",
	"res://assets/original/3d/models/fanqing_grass_cut.glb",
]
const LANTERN_MODELS: PackedStringArray = [
	"res://assets/original/3d/models/qi_eating_whelp.glb",
	"res://assets/original/3d/models/stone_spitter.glb",
	"res://assets/original/3d/models/spirit_gnawer.glb",
	"res://assets/original/3d/models/qi_eating_stone_beast.glb",
	"res://assets/original/3d/models/lantern_array_pillar_lit.glb",
	"res://assets/original/3d/models/lantern_array_pillar_spent.glb",
	"res://assets/original/3d/models/lantern_core.glb",
	"res://assets/original/3d/models/foundation_altar.glb",
]
const LANTERN_ENEMY_SCENES: PackedStringArray = [
	"res://game/roadside/action_combat_3d/characters/qi_beast_3d.tscn",
	"res://game/roadside/action_combat_3d/characters/stone_spitter_3d.tscn",
	"res://game/roadside/action_combat_3d/characters/spirit_gnawer_3d.tscn",
	"res://game/roadside/action_combat_3d/characters/qi_eating_stone_beast_3d.tscn",
]
const LANTERN_PILLAR_SCENE := (
	"res://game/roadside/action_combat_3d/props/lantern_array_pillar_3d.tscn"
)


static func validate_assets() -> PackedStringArray:
	var errors := PackedStringArray()
	var manifest := _load_manifest(errors)
	_validate_manifest_files(manifest, errors)
	for path: String in CHARACTER_MODELS:
		_validate_character_model(path, errors)
	for path: String in CHARACTER_SCENES:
		_validate_character_scene(path, errors)
	for path: String in ENVIRONMENT_SCENES:
		_validate_environment_scene(path, errors)
	for path: String in PLANT_MODELS:
		_validate_static_model(path, errors)
	for path: String in LANTERN_MODELS:
		_validate_static_model(path, errors)
	for path: String in LANTERN_ENEMY_SCENES:
		_validate_enemy_scene(path, errors)
	_validate_lantern_pillar_scene(errors)
	_validate_shared_animation_tracks(errors)
	_validate_palette(errors)
	return errors


static func _load_manifest(errors: PackedStringArray) -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		errors.append("3D asset manifest is missing: %s" % MANIFEST_PATH)
		return {}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		errors.append("3D asset manifest is invalid JSON")
		return {}
	var manifest: Dictionary = json.data
	if int(manifest.get("schema_version", 0)) != 1:
		errors.append("3D asset manifest has an unsupported schema_version")
	var animation_names := PackedStringArray()
	for animation: StringName in REQUIRED_ANIMATIONS:
		animation_names.append(String(animation))
	if PackedStringArray(manifest.get("required_animations", [])) != animation_names:
		errors.append("3D asset manifest does not declare the six required animations")
	return manifest


static func _validate_manifest_files(manifest: Dictionary, errors: PackedStringArray) -> void:
	var assets: Variant = manifest.get("assets")
	if not assets is Array or assets.size() < 24:
		errors.append("3D asset manifest should contain the complete candidate set")
		return
	for raw_record: Variant in assets:
		if not raw_record is Dictionary:
			errors.append("3D asset manifest contains a non-object record")
			continue
		var path := "res://%s" % String(raw_record.get("path", ""))
		if not FileAccess.file_exists(path):
			errors.append("3D asset output is missing: %s" % path)
			continue
		var expected_hash := String(raw_record.get("sha256", ""))
		if expected_hash.is_empty() or _sha256(path) != expected_hash:
			errors.append("3D asset output hash differs from manifest: %s" % path)


static func _validate_character_model(path: String, errors: PackedStringArray) -> void:
	var instance := _instantiate(path, errors)
	if instance == null:
		return
	var skeleton := _find_skeleton(instance)
	var player := _find_animation_player(instance)
	var meshes := _find_meshes(instance)
	if skeleton == null:
		errors.append("Rigged character has no Skeleton3D: %s" % path)
	else:
		if skeleton.get_bone_count() != REQUIRED_BONES.size():
			errors.append("Rigged character has the wrong bone count: %s" % path)
		elif skeleton.get_concatenated_bone_names() != ",".join(REQUIRED_BONES):
			errors.append("Rigged character bone names differ from shared rig: %s" % path)
	if player == null:
		errors.append("Rigged character has no AnimationPlayer: %s" % path)
	else:
		for animation_name: StringName in REQUIRED_ANIMATIONS:
			if not player.has_animation(animation_name):
				errors.append("Rigged character is missing %s: %s" % [animation_name, path])
			else:
				_validate_animation_motion(
					player.get_animation(animation_name),
					animation_name,
					path,
					errors
				)
	if meshes.is_empty():
		errors.append("Rigged character has no MeshInstance3D: %s" % path)
	else:
		var bounds := AABB()
		var first := true
		var triangles := 0
		for mesh_instance: MeshInstance3D in meshes:
			if mesh_instance.mesh == null:
				continue
			bounds = mesh_instance.mesh.get_aabb() if first else bounds.merge(mesh_instance.mesh.get_aabb())
			first = false
			triangles += _mesh_triangle_count(mesh_instance.mesh)
			_validate_mesh_materials(mesh_instance.mesh, path, errors)
		if triangles > 2000:
			errors.append("Rigged character exceeds 2000 triangles: %s" % path)
		if not first and (bounds.position.y < -0.02 or bounds.end.y < 1.8 or bounds.end.y > 2.4):
			errors.append("Rigged character has invalid foot origin or height: %s" % path)
	instance.free()


static func _validate_character_scene(path: String, errors: PackedStringArray) -> void:
	var instance := _instantiate(path, errors)
	if instance == null:
		return
	if not instance is CharacterBody3D:
		errors.append("Character wrapper root is not CharacterBody3D: %s" % path)
	if instance.scale != Vector3.ONE:
		errors.append("Character wrapper must use unit scale: %s" % path)
	var collision := instance.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if collision == null or collision.shape == null:
		errors.append("Character wrapper has no collision shape: %s" % path)
	if instance.find_child("NavigationAgent3D", true, false) == null:
		errors.append("Character wrapper has no NavigationAgent3D: %s" % path)
	instance.free()


static func _validate_environment_scene(path: String, errors: PackedStringArray) -> void:
	var instance := _instantiate(path, errors)
	if instance == null:
		return
	if not instance is StaticBody3D:
		errors.append("Environment module root is not StaticBody3D: %s" % path)
	if instance.scale != Vector3.ONE:
		errors.append("Environment module must use unit scale: %s" % path)
	var collision := instance.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if collision == null or collision.shape == null:
		errors.append("Environment module has no collision: %s" % path)
	var meshes := _find_meshes(instance)
	if meshes.is_empty():
		errors.append("Environment module has no imported mesh: %s" % path)
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh != null:
			if _mesh_triangle_count(mesh_instance.mesh) > 1000:
				errors.append("Environment module exceeds 1000 triangles: %s" % path)
			_validate_mesh_materials(mesh_instance.mesh, path, errors)
	instance.free()


static func _validate_enemy_scene(path: String, errors: PackedStringArray) -> void:
	var instance := _instantiate(path, errors)
	if instance == null:
		return
	if not instance is CharacterBody3D:
		errors.append("Lantern enemy wrapper root is not CharacterBody3D: %s" % path)
	if instance.get_node_or_null(^"Model") == null:
		errors.append("Lantern enemy wrapper has no formal Model: %s" % path)
	var collision := instance.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if collision == null or collision.shape == null:
		errors.append("Lantern enemy wrapper has no collision shape: %s" % path)
	var hurtbox := instance.get_node_or_null(^"Hurtbox") as Area3D
	if hurtbox == null or hurtbox.get_node_or_null(^"CollisionShape3D") == null:
		errors.append("Lantern enemy wrapper has no hurtbox: %s" % path)
	if instance.get_node_or_null(^"Telegraph") == null:
		errors.append("Lantern enemy wrapper has no telegraph: %s" % path)
	instance.free()


static func _validate_lantern_pillar_scene(errors: PackedStringArray) -> void:
	var instance := _instantiate(LANTERN_PILLAR_SCENE, errors)
	if instance == null:
		return
	if not instance is StaticBody3D:
		errors.append("Lantern array pillar root is not StaticBody3D")
	for node_name: StringName in [&"LitModel", &"SpentModel", &"Light"]:
		if instance.get_node_or_null(NodePath(String(node_name))) == null:
			errors.append("Lantern array pillar is missing %s" % node_name)
	var collision := instance.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if collision == null or collision.shape == null:
		errors.append("Lantern array pillar has no collision shape")
	instance.free()


static func _validate_static_model(path: String, errors: PackedStringArray) -> void:
	var instance := _instantiate(path, errors)
	if instance == null:
		return
	var meshes := _find_meshes(instance)
	if meshes.is_empty():
		errors.append("Static 3D model has no imported mesh: %s" % path)
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		if _mesh_triangle_count(mesh_instance.mesh) > 500:
			errors.append("Static 3D model exceeds 500 triangles: %s" % path)
		_validate_mesh_materials(mesh_instance.mesh, path, errors)
	instance.free()


static func _validate_shared_animation_tracks(errors: PackedStringArray) -> void:
	var base := _instantiate(CHARACTER_MODELS[0], errors)
	var variant := _instantiate(CHARACTER_MODELS[1], errors)
	if base == null or variant == null:
		if base != null:
			base.free()
		if variant != null:
			variant.free()
		return
	var base_player := _find_animation_player(base)
	var variant_player := _find_animation_player(variant)
	if base_player != null and variant_player != null:
		for animation_name: StringName in REQUIRED_ANIMATIONS:
			var base_animation := base_player.get_animation(animation_name)
			var variant_animation := variant_player.get_animation(animation_name)
			if base_animation == null or variant_animation == null:
				continue
			if _animation_paths(base_animation) != _animation_paths(variant_animation):
				errors.append("Shared animation tracks differ for %s" % animation_name)
	base.free()
	variant.free()


static func _validate_animation_motion(
	animation: Animation,
	animation_name: StringName,
	path: String,
	errors: PackedStringArray
) -> void:
	if animation == null or animation.length <= 0.0 or animation.get_track_count() == 0:
		errors.append("Rigged character has an empty %s animation: %s" % [animation_name, path])
		return
	var has_motion := false
	var idle_has_relaxed_arm := animation_name != &"idle"
	for track: int in range(animation.get_track_count()):
		var key_count := animation.track_get_key_count(track)
		if key_count == 0:
			continue
		var first_value: Variant = animation.track_get_key_value(track, 0)
		for key: int in range(1, key_count):
			if animation.track_get_key_value(track, key) != first_value:
				has_motion = true
				break
		if (
			animation_name == &"idle"
			and String(animation.track_get_path(track)).contains("upper_arm_l")
			and first_value is Quaternion
			and not (first_value as Quaternion).is_equal_approx(Quaternion.IDENTITY)
		):
			idle_has_relaxed_arm = true
	if not has_motion:
		errors.append("Rigged character animation has no pose change for %s: %s" % [animation_name, path])
	if not idle_has_relaxed_arm:
		errors.append("Rigged character idle begins from a binding arm pose: %s" % path)


static func _validate_palette(errors: PackedStringArray) -> void:
	var path := "res://assets/original/3d/textures/original_lowpoly_palette.png"
	var texture := load(path) as Texture2D
	if texture == null or texture.get_size() != Vector2(4, 4):
		errors.append("Original 3D palette texture should be exactly 4x4: %s" % path)


static func _instantiate(path: String, errors: PackedStringArray) -> Node:
	var packed := load(path) as PackedScene
	if packed == null or not packed.can_instantiate():
		errors.append("3D asset scene cannot instantiate: %s" % path)
		return null
	return packed.instantiate()


static func _find_skeleton(root: Node) -> Skeleton3D:
	return root.find_child("Skeleton3D", true, false) as Skeleton3D


static func _find_animation_player(root: Node) -> AnimationPlayer:
	return root.find_child("AnimationPlayer", true, false) as AnimationPlayer


static func _find_meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for candidate: Node in root.find_children("*", "MeshInstance3D", true, false):
		result.append(candidate as MeshInstance3D)
	return result


static func _mesh_triangle_count(mesh: Mesh) -> int:
	var count := 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices != null and indices.size() > 0:
			count += indices.size() / 3
		else:
			count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return count


static func _validate_mesh_materials(
	mesh: Mesh,
	path: String,
	errors: PackedStringArray
) -> void:
	for surface: int in range(mesh.get_surface_count()):
		if mesh.surface_get_material(surface) == null:
			errors.append("3D mesh surface has no material: %s surface %d" % [path, surface])


static func _animation_paths(animation: Animation) -> PackedStringArray:
	var paths := PackedStringArray()
	for track: int in range(animation.get_track_count()):
		paths.append(String(animation.track_get_path(track)))
	return paths


static func _sha256(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()
