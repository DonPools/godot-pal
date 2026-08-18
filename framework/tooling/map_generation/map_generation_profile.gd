@tool
class_name MapGenerationProfile
extends Resource

const SOURCE_PATH_META: StringName = &"map_generation_source_path"

enum TargetMode {
	TILEMAP_2D,
	MODULES_3D,
}

@export var schema_version: int = 1
@export var target_mode: TargetMode = TargetMode.TILEMAP_2D
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
@export var cell_size_3d: Vector2 = Vector2(4.0, 4.0)
@export var world_origin_3d: Vector3 = Vector3.ZERO


func set_authoring_source_path(path: String) -> void:
	set_meta(SOURCE_PATH_META, path)


func authoring_source_path() -> String:
	return (
		resource_path
		if not resource_path.is_empty()
		else String(get_meta(SOURCE_PATH_META, ""))
	)


func uses_3d_modules() -> bool:
	return target_mode == TargetMode.MODULES_3D


func cell_to_world(cell: Vector2i, y_offset: float = 0.0) -> Vector3:
	var relative := Vector2(cell - map_origin)
	var centre := Vector2(map_size - Vector2i.ONE) * 0.5
	return world_origin_3d + Vector3(
		(relative.x - centre.x) * cell_size_3d.x,
		y_offset,
		(relative.y - centre.y) * cell_size_3d.y
	)


func world_to_cell(position: Vector3) -> Vector2i:
	var centre := Vector2(map_size - Vector2i.ONE) * 0.5
	var relative := Vector2(
		(position.x - world_origin_3d.x) / cell_size_3d.x,
		(position.z - world_origin_3d.z) / cell_size_3d.y
	) + centre
	return map_origin + Vector2i(roundi(relative.x), roundi(relative.y))
