@tool
class_name MapGenerationTile
extends Resource

@export var source_id: int = 0
@export var atlas_coords: Vector2i = Vector2i.ZERO
@export var alternative_tile: int = 0


func is_valid_for(tile_set: TileSet) -> bool:
	if tile_set == null or not tile_set.has_source(source_id):
		return false
	var atlas_source := tile_set.get_source(source_id) as TileSetAtlasSource
	return atlas_source != null and atlas_source.has_tile(atlas_coords)


func to_dictionary() -> Dictionary:
	return {
		"source_id": source_id,
		"atlas_x": atlas_coords.x,
		"atlas_y": atlas_coords.y,
		"alternative_tile": alternative_tile,
	}
