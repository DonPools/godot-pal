class_name DirectionalSpriteFrames
extends RefCounted

const COLUMNS := 3
const ROWS := 4
const DIRECTIONS: Array[StringName] = [&"south", &"west", &"north", &"east"]


static func from_3x4_sheet(texture: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	if texture == null or texture.get_width() % COLUMNS != 0 or texture.get_height() % ROWS != 0:
		return frames
	var frame_size := Vector2i(texture.get_width() / COLUMNS, texture.get_height() / ROWS)
	for row: int in range(DIRECTIONS.size()):
		var animation := DIRECTIONS[row]
		frames.add_animation(animation)
		frames.set_animation_loop(animation, true)
		frames.set_animation_speed(animation, 7.0)
		for column: int in [1, 0, 1, 2]:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(
				Vector2(column * frame_size.x, row * frame_size.y),
				frame_size
			)
			frames.add_frame(animation, atlas)
	return frames


static func visual_offset(texture: Texture2D) -> Vector2:
	return Vector2(0.0, -float(texture.get_height() / ROWS) * 0.5)
