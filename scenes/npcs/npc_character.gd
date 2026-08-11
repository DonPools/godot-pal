class_name NpcCharacter
extends CharacterBody2D

@export var sprite_source_id: int = 21
@export var initial_direction: StringName = &"south"
@export var fallback_color: Color = Color(0.62, 0.38, 0.7)

@onready var visual: AnimatedSprite2D = $Visual


func configure(assets: AssetLibrary) -> void:
	visual.sprite_frames = assets.character_frames(sprite_source_id, fallback_color)
	visual.position = assets.character_visual_offset(sprite_source_id)
	visual.play(initial_direction)
	visual.pause()
