class_name MapBattlePresentation3D
extends RefCounted

const PROJECTILE_SCENE := preload(
	"res://framework/presentation/action_combat_3d/battle_projectile_3d.tscn"
)
const PLAYER_HIT_STOP_SECONDS := 0.065
const ENEMY_HIT_STOP_SECONDS := 0.045
const REDUCED_HIT_STOP_SCALE := 0.35

var _map_scene: MapGameScene3D
var _settings: SettingsService
var _hit_stop_remaining: float = 0.0
var _hit_stop_physics_states: Array[Dictionary] = []


func configure(map_scene: MapGameScene3D, settings: SettingsService) -> void:
	_map_scene = map_scene
	_settings = settings


func advance_hit_stop(delta: float) -> bool:
	if _hit_stop_remaining <= 0.0:
		return false
	_hit_stop_remaining = maxf(_hit_stop_remaining - delta, 0.0)
	if _hit_stop_remaining <= 0.0:
		restore_hit_stop_motion()
	return true


func spawn_projectile(
	actor_id: StringName,
	action_instance_id: int,
	origin: Vector3,
	direction: Vector3,
	speed_override: float = 0.0
) -> void:
	var session := _map_scene.current_battle_session()
	if session == null:
		return
	var projectile := PROJECTILE_SCENE.instantiate() as BattleProjectile3D
	_map_scene.world_root.add_child(projectile)
	projectile.global_position = origin
	var actor := session.actor(actor_id)
	var speed := speed_override
	var max_range := 9.0
	if actor != null and actor.current_action != null and actor.current_action.intent.skill != null:
		max_range = actor.current_action.intent.skill.max_range
	if speed <= 0.0:
		speed = 9.0
	var returns_to_origin := session.projectile_returns(action_instance_id)
	projectile.configure(
		_map_scene,
		actor_id,
		action_instance_id,
		direction,
		speed,
		actor_id != session.player.id,
		(max_range / speed) * (2.0 if returns_to_origin else 1.0),
		returns_to_origin,
		session.projectile_pierces(action_instance_id)
	)


func show_damage_number(position_3d: Vector3, amount: int, enemy_damage: bool) -> void:
	var label := Label.new()
	label.text = str(amount)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.82, 0.32) if enemy_damage else Color(1.0, 0.35, 0.28)
	)
	label.position = (
		_map_scene.camera_3d.unproject_position(position_3d) - Vector2(18.0, 12.0)
	)
	_map_scene.get_node(^"HudLayer").add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 24.0, 0.55)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.55)
	tween.tween_callback(label.queue_free)


func show_area_skill_effect(
	position_3d: Vector3,
	radius: float,
	color: Color
) -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.035
	mesh.material = material
	var effect := MeshInstance3D.new()
	effect.mesh = mesh
	_map_scene.world_root.add_child(effect)
	effect.global_position = position_3d + Vector3.UP * 0.06
	effect.scale = Vector3(0.15, 1.0, 0.15)
	var tween := effect.create_tween()
	tween.tween_property(effect, "scale", Vector3(radius, 1.0, radius), 0.22)
	tween.tween_interval(0.12)
	tween.tween_callback(effect.queue_free)


func show_event_feedback(event: BattleEvent) -> void:
	var session := _map_scene.current_battle_session()
	if session == null:
		return
	match event.kind:
		BattleEvent.Kind.ACTION_ACTIVE:
			if event.actor_id == session.player.id:
				var actor := session.actor(event.actor_id)
				var empowered := (
					actor != null
					and actor.current_action != null
					and actor.current_action.intent.skill != null
				)
				_map_scene.combat_feedback.show_slash(
					_map_scene.player_3d.global_position + Vector3.UP * 0.92,
					_map_scene.player_3d.aim_direction(),
					empowered
				)
		BattleEvent.Kind.DODGE_STARTED:
			if event.actor_id == session.player.id:
				var dodge_direction := _map_scene.player_3d.movement_direction()
				_map_scene.combat_feedback.show_dodge_afterimages(
					_map_scene.player_3d,
					dodge_direction
					if not dodge_direction.is_zero_approx()
					else _map_scene.player_3d.aim_direction()
				)
		BattleEvent.Kind.DAMAGE:
			var target := _actor_view(event.target_id, session)
			if target == null:
				return
			var player_was_hit := event.target_id == session.player.id
			_map_scene.combat_feedback.flash_actor(target, player_was_hit)
			_map_scene.combat_feedback.show_hit_spark(
				target.global_position + Vector3.UP * (1.0 if player_was_hit else 0.82),
				player_was_hit
			)
			start_hit_stop(
				PLAYER_HIT_STOP_SECONDS if player_was_hit else ENEMY_HIT_STOP_SECONDS
			)


func start_hit_stop(duration: float) -> void:
	var applied_duration := duration
	if _settings != null and _settings.reduce_combat_flashes:
		applied_duration *= REDUCED_HIT_STOP_SCALE
	_hit_stop_remaining = maxf(_hit_stop_remaining, applied_duration)
	if not _hit_stop_physics_states.is_empty():
		return
	for candidate: Node in _map_scene.get_tree().get_nodes_in_group(&"battle_motion_3d"):
		if not _map_scene.is_ancestor_of(candidate):
			continue
		_hit_stop_physics_states.append({
			"candidate": weakref(candidate),
			"was_processing": candidate.is_physics_processing(),
		})
		candidate.set_physics_process(false)


func restore_hit_stop_motion() -> void:
	_hit_stop_remaining = 0.0
	for state: Dictionary in _hit_stop_physics_states:
		var reference := state.get("candidate") as WeakRef
		var candidate := reference.get_ref() as Node if reference != null else null
		if candidate != null and is_instance_valid(candidate):
			candidate.set_physics_process(bool(state.get("was_processing", false)))
	_hit_stop_physics_states.clear()


func is_hit_stop_active() -> bool:
	return _hit_stop_remaining > 0.0


func hit_stop_remaining_seconds() -> float:
	return _hit_stop_remaining


func paused_battle_motion_count() -> int:
	return _hit_stop_physics_states.size()


func _actor_view(actor_id: StringName, session: BattleSession) -> Node3D:
	if actor_id == session.player.id:
		return _map_scene.player_3d
	for enemy_view: EnemyActorView3D in _map_scene.enemy_views():
		if enemy_view.actor_id == actor_id:
			return enemy_view
	return null
