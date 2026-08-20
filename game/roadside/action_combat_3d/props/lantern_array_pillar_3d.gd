class_name LanternArrayPillar3D
extends StaticBody3D

@export var pillar_id: StringName

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var light: OmniLight3D = $Light
@onready var lit_model: Node3D = $LitModel
@onready var spent_model: Node3D = $SpentModel

var _map_scene: MapGameScene


func _ready() -> void:
	add_to_group(&"battle_array_pillars")
	set_meta(&"pillar_id", String(pillar_id))
	_map_scene = _find_map_scene()
	if _map_scene != null:
		_map_scene.battle_started.connect(_on_battle_started)
		_map_scene.battle_events_produced.connect(_on_battle_events)
	_reset_pillar()


func _on_battle_started(_session: BattleSession) -> void:
	_reset_pillar()


func _on_battle_events(events: Array[BattleEvent]) -> void:
	for event: BattleEvent in events:
		if event.kind == BattleEvent.Kind.PILLAR_CONSUMED and event.target_id == pillar_id:
			collision_shape.set_deferred("disabled", true)
			light.light_energy = 0.0
			lit_model.visible = false
			spent_model.visible = true


func _reset_pillar() -> void:
	collision_shape.set_deferred("disabled", false)
	light.light_energy = 2.2
	lit_model.visible = true
	spent_model.visible = false


func _find_map_scene() -> MapGameScene:
	var current: Node = self
	while current != null:
		if current is MapGameScene:
			return current as MapGameScene
		current = current.get_parent()
	return null
