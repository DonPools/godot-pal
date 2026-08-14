class_name NpcCharacter
extends CharacterBody2D

@export var sprite_sheet: Texture2D
@export var initial_direction: StringName = &"south"

@onready var visual: AnimatedSprite2D = $Visual


func configure() -> void:
	if sprite_sheet == null:
		push_error("NpcCharacter requires a sprite_sheet")
		return
	visual.sprite_frames = DirectionalSpriteFrames.from_3x4_sheet(sprite_sheet)
	visual.position = DirectionalSpriteFrames.visual_offset(sprite_sheet)
	visual.play(initial_direction)
	visual.pause()
