class_name WorldProp
extends Node2D

@export var tile_source_id: int = 12
@export var tile_frame_index: int = 176
@export var fallback_color: Color = Color(0.4, 0.62, 0.76)

@onready var visual: Sprite2D = $Visual


func configure(assets: AssetLibrary) -> void:
	var texture := assets.tile_frame(tile_source_id, tile_frame_index)
	if texture != null:
		visual.texture = texture
		return
	var image := Image.create(14, 20, false, Image.FORMAT_RGBA8)
	image.fill(fallback_color)
	visual.texture = ImageTexture.create_from_image(image)
