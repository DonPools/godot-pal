class_name BattleHurtbox3D
extends PointerTarget3D

var actor_id: StringName


func _ready() -> void:
	super._ready()
	add_to_group(&"battle_hurtboxes_3d")


func configure(value: StringName) -> void:
	actor_id = value
