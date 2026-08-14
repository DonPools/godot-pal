class_name WorldProp
extends Node2D

@export var texture: Texture2D

@onready var visual: Sprite2D = $Visual


func configure() -> void:
	visual.texture = texture
