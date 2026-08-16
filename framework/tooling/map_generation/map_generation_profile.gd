@tool
class_name MapGenerationProfile
extends Resource

const SOURCE_PATH_META: StringName = &"map_generation_source_path"

@export var schema_version: int = 1
@export var seed: int = 1
@export var target_scene_path: String = ""
@export var map_origin: Vector2i = Vector2i.ZERO
@export var map_size: Vector2i = Vector2i(32, 16)
@export var biome: MapGenerationBiome
@export var anchors: Array[MapGenerationAnchor] = []
@export_range(0.001, 1.0, 0.001) var elevation_frequency: float = 0.055
@export_range(0.001, 1.0, 0.001) var moisture_frequency: float = 0.07
@export_range(0.001, 1.0, 0.001) var fertility_frequency: float = 0.09
@export_range(0.001, 1.0, 0.001) var spirit_frequency: float = 0.045
@export_range(1, 5, 1) var road_width_cells: int = 1
@export_range(0, 10000, 1) var maximum_generated_props: int = 160


func set_authoring_source_path(path: String) -> void:
	set_meta(SOURCE_PATH_META, path)


func authoring_source_path() -> String:
	return (
		resource_path
		if not resource_path.is_empty()
		else String(get_meta(SOURCE_PATH_META, ""))
	)
