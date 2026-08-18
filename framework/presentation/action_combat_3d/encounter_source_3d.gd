class_name EncounterSource3D
extends Node3D

signal encounter_alerted(source: EncounterSource3D)
signal enemy_returned_home(source: EncounterSource3D)

@export var persistent_id: StringName
@export var trigger_id: StringName = &"default"
@export var encounter: BattleEncounter
@export var event: StoryEvent

var binding := StoryBinding.new()
var enemy_views: Array[EnemyActorView3D] = []
var triggering: bool = false

var _map_scene: MapGameScene
var _enemy_root: Node3D
var _player: PlayerCharacter3D


func prepare(
	map_scene: MapGameScene,
	enemy_root: Node3D,
	player: PlayerCharacter3D
) -> void:
	_map_scene = map_scene
	_enemy_root = enemy_root
	_player = player
	binding.event = event
	binding.trigger_id = trigger_id
	if (
		persistent_id.is_empty()
		or encounter == null
		or event == null
	):
		push_error("EncounterSource3D requires persistent_id, encounter, and event")
		return
	if map_scene.scene_context.game_run.world.is_completed(map_scene.map_id, persistent_id):
		apply_completed()
		return
	_spawn_enemy_views()


func begin_session(session: BattleSession) -> void:
	for enemy_view: EnemyActorView3D in enemy_views:
		enemy_view.begin_session(session)


func request_alert() -> void:
	if not triggering:
		encounter_alerted.emit(self)


func notify_enemy_home() -> void:
	enemy_returned_home.emit(self)


func reset_after_escape() -> void:
	triggering = false
	for enemy_view: EnemyActorView3D in enemy_views:
		enemy_view.reset_dormant()


func story_origin(map_id: StringName) -> StoryOrigin:
	return StoryOrigin.create(map_id, persistent_id)


func apply_completed() -> void:
	triggering = false
	for enemy_view: EnemyActorView3D in enemy_views:
		if is_instance_valid(enemy_view):
			enemy_view.queue_free()
	enemy_views.clear()
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


func all_living_enemies_home() -> bool:
	for enemy_view: EnemyActorView3D in enemy_views:
		if not enemy_view.is_defeated() and not enemy_view.is_dormant_at_home():
			return false
	return true


func _spawn_enemy_views() -> void:
	for entry: EncounterEnemy in encounter.enemies:
		if entry == null or entry.enemy == null or entry.enemy.character_scene == null:
			continue
		var instance := entry.enemy.character_scene.instantiate()
		if not instance is EnemyActorView3D:
			push_error("Enemy scene for %s must use EnemyActorView3D" % entry.enemy.id)
			instance.free()
			continue
		var enemy_view := instance as EnemyActorView3D
		_enemy_root.add_child(enemy_view)
		enemy_view.global_position = global_position + entry.spawn_offset
		enemy_view.configure_dormant(_map_scene, _player, entry)
		enemy_view.alert_requested.connect(request_alert)
		enemy_view.returned_home.connect(notify_enemy_home)
		enemy_views.append(enemy_view)
