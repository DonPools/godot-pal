class_name BattleHurtbox3D
extends Area3D

var actor_id: StringName


func _ready() -> void:
	add_to_group(&"battle_hurtboxes_3d")


func configure(value: StringName) -> void:
	actor_id = value
