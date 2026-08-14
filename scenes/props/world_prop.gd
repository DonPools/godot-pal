class_name WorldProp
extends Node2D

@export var texture: Texture2D

@onready var visual: Sprite2D = $Visual


func configure(_game_run: GameRun = null, _map_id: StringName = &"") -> void:
	visual.texture = texture


func refresh() -> void:
	pass
