class_name AssetLibrary
extends Node

const GENERATED_ROOT := "res://generated/"
const MANIFEST_PATH := GENERATED_ROOT + "manifest.json"

var using_generated_assets: bool = false
var diagnostic: String = "required generated asset manifest is unavailable"
var diagnostics: Array[Dictionary] = []

var _assets_by_key: Dictionary[String, Dictionary] = {}
var _fallback_tile_atlas: Dictionary = {}


func initialize() -> void:
	_load_manifest()
	if not using_generated_assets:
		for entry: Dictionary in diagnostics:
			push_error(JSON.stringify(entry))


func character_frames(source_id: int, fallback_color: Color) -> SpriteFrames:
	var entry := _entry("MGO.MKF", source_id)
	if entry.is_empty():
		return _fallback_character_frames(fallback_color)
	var texture := _load_texture(String(entry.get("path", "")))
	var metadata: Dictionary = entry.get("metadata", {})
	var raw_cell: Array = metadata.get("cell_size", [])
	var raw_frames: Array = metadata.get("frames", [])
	if texture == null or raw_cell.size() != 2 or raw_frames.size() < 12:
		return _fallback_character_frames(fallback_color)
	var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	var textures: Array[Texture2D] = []
	for raw_frame: Variant in raw_frames:
		if not (raw_frame is Dictionary):
			continue
		var raw_atlas: Variant = raw_frame.get("atlas")
		if not (raw_atlas is Array and raw_atlas.size() == 2):
			continue
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = texture
		atlas_texture.region = Rect2(
			int(raw_atlas[0]) * cell.x,
			int(raw_atlas[1]) * cell.y,
			cell.x,
			cell.y
		)
		atlas_texture.filter_clip = true
		textures.append(atlas_texture)
	if textures.size() < 12:
		return _fallback_character_frames(fallback_color)
	return _directional_frames(textures)


func character_visual_offset(source_id: int) -> Vector2:
	var entry := _entry("MGO.MKF", source_id)
	if entry.is_empty():
		return Vector2(0.0, -12.0)
	var metadata: Dictionary = entry.get("metadata", {})
	var cell: Variant = metadata.get("cell_size")
	if cell is Array and cell.size() == 2:
		return Vector2(0.0, -float(cell[1]) * 0.5)
	return Vector2(0.0, -12.0)


func tile_atlas(source_id: int) -> Dictionary:
	var entry := _entry("GOP.MKF", source_id)
	if entry.is_empty():
		return _fallback_tiles()
	var texture := _load_texture(String(entry.get("path", "")))
	var metadata: Dictionary = entry.get("metadata", {})
	var raw_cell: Variant = metadata.get("cell_size")
	var raw_frames: Variant = metadata.get("frames")
	if texture == null or not (raw_cell is Array and raw_cell.size() == 2):
		return _fallback_tiles()
	if not (raw_frames is Array and not raw_frames.is_empty()):
		return _fallback_tiles()
	return {
		"texture": texture,
		"cell_size": Vector2i(int(raw_cell[0]), int(raw_cell[1])),
		"columns": int(metadata.get("columns", 1)),
		"frame_count": raw_frames.size(),
	}


func tile_frame(source_id: int, frame_index: int) -> Texture2D:
	var atlas := tile_atlas(source_id)
	var texture: Texture2D = atlas.get("texture")
	var cell: Vector2i = atlas.get("cell_size", Vector2i(32, 16))
	var columns: int = atlas.get("columns", 1)
	var count: int = atlas.get("frame_count", 0)
	if texture == null or frame_index < 0 or frame_index >= count:
		return null
	var result := AtlasTexture.new()
	result.atlas = texture
	result.region = Rect2(
		(frame_index % columns) * cell.x,
		(frame_index / columns) * cell.y,
		cell.x,
		cell.y
	)
	result.filter_clip = true
	return result


func ui_frame(source_chunk: int, source_frame_index: int) -> Texture2D:
	var entry := _entry("DATA.MKF", source_chunk)
	if entry.is_empty():
		return null
	var texture := _load_texture(String(entry.get("path", "")))
	var metadata: Dictionary = entry.get("metadata", {})
	var raw_cell: Variant = metadata.get("cell_size")
	var raw_frames: Variant = metadata.get("frames")
	if texture == null or not (raw_cell is Array and raw_cell.size() == 2):
		return null
	if not (raw_frames is Array):
		return null
	for raw_frame: Variant in raw_frames:
		if not (raw_frame is Dictionary) or int(raw_frame.get("index", -1)) != source_frame_index:
			continue
		var raw_atlas: Variant = raw_frame.get("atlas")
		if not (raw_atlas is Array and raw_atlas.size() == 2):
			return null
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		var result := AtlasTexture.new()
		result.atlas = texture
		result.region = Rect2(
			int(raw_atlas[0]) * cell.x,
			int(raw_atlas[1]) * cell.y,
			cell.x,
			cell.y
		)
		result.filter_clip = true
		return result
	return null


func portrait(source_id: int, fallback_color: Color) -> Texture2D:
	var entry := _entry("RGM.MKF", source_id)
	if not entry.is_empty():
		var texture := _load_texture(String(entry.get("path", "")))
		if texture != null:
			return texture
	var image := Image.create(48, 58, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.04, 0.04, 0.06, 1.0))
	for y: int in range(8, 52):
		for x: int in range(8, 40):
			if Vector2(x - 24, y - 28).length() < 18.0:
				image.set_pixel(x, y, fallback_color)
	return ImageTexture.create_from_image(image)


func dialogue_font() -> Font:
	var path := GENERATED_ROOT + "fonts/pal_bitmap_16.fnt"
	if using_generated_assets and ResourceLoader.exists(path):
		var font := load(path) as Font
		if font != null:
			return font
	return ThemeDB.fallback_font


func music(source_id: int) -> AudioStream:
	return _audio_stream("MUS.MKF", source_id)


func sound(source_id: int) -> AudioStream:
	return _audio_stream("VOC.MKF", source_id)


func _audio_stream(file: String, source_id: int) -> AudioStream:
	var entry := _entry(file, source_id)
	if entry.is_empty():
		return null
	var path := GENERATED_ROOT + String(entry.get("path", ""))
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func _load_manifest() -> void:
	_assets_by_key.clear()
	using_generated_assets = false
	diagnostics.clear()
	var validation := AssetManifestValidator.new().validate_file(MANIFEST_PATH, GENERATED_ROOT)
	diagnostics.assign(validation.get("diagnostics", []))
	if not diagnostics.is_empty():
		diagnostic = String(diagnostics[0].get("message", "generated asset validation failed"))
		return
	var parsed: Dictionary = validation.get("manifest", {})
	var entries: Array = parsed.get("assets", [])
	for raw_entry: Variant in entries:
		var source: Dictionary = raw_entry.get("source", {})
		var file_name := String(source.get("file", ""))
		var chunk := int(source.get("chunk", -1))
		_assets_by_key[_key(file_name, chunk)] = raw_entry
	using_generated_assets = true
	diagnostic = "framework-lab generated assets loaded and verified"


func _entry(file: String, chunk: int) -> Dictionary:
	return _assets_by_key.get(_key(file, chunk), {})


func _key(file: String, chunk: int) -> String:
	return "%s:%d" % [file, chunk]


func _load_texture(relative_path: String) -> Texture2D:
	if relative_path.is_empty():
		return null
	var path := GENERATED_ROOT + relative_path
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _directional_frames(textures: Array[Texture2D]) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var names: Array[StringName] = [&"south", &"west", &"north", &"east"]
	for direction_index: int in range(names.size()):
		var animation: StringName = names[direction_index]
		frames.add_animation(animation)
		frames.set_animation_loop(animation, true)
		frames.set_animation_speed(animation, 7.0)
		var base := direction_index * 3
		for offset: int in [0, 1, 0, 2]:
			frames.add_frame(animation, textures[base + offset])
	return frames


func _fallback_character_frames(color: Color) -> SpriteFrames:
	var image := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in range(5, 24):
		for x: int in range(3, 13):
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	var textures: Array[Texture2D] = []
	for _index: int in range(12):
		textures.append(texture)
	return _directional_frames(textures)


func _fallback_tiles() -> Dictionary:
	if not _fallback_tile_atlas.is_empty():
		return _fallback_tile_atlas
	var columns := 16
	var rows := 8
	var cell := Vector2i(32, 16)
	var image := Image.create(columns * cell.x, rows * cell.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for index: int in range(columns * rows):
		var origin := Vector2i((index % columns) * cell.x, (index / columns) * cell.y)
		var color := Color.from_hsv(float(index % 12) / 12.0, 0.35, 0.48 + 0.08 * (index % 2))
		for y: int in range(cell.y):
			var half_width: int = mini(y + 1, cell.y - y) * 2
			for x: int in range(cell.x / 2 - half_width, cell.x / 2 + half_width):
				if x >= 0 and x < cell.x:
					image.set_pixel(origin.x + x, origin.y + y, color)
	_fallback_tile_atlas = {
		"texture": ImageTexture.create_from_image(image),
		"cell_size": cell,
		"columns": columns,
		"frame_count": columns * rows,
	}
	return _fallback_tile_atlas
