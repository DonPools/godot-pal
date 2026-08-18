@tool
class_name MapGenerationPropRule
extends Resource

@export var id: StringName
@export var scene: PackedScene
@export var scene_3d: PackedScene
@export var allowed_terrain_tags: Array[StringName] = []
@export_range(0.0, 1.0, 0.001) var density: float = 0.05
@export_range(0, 16, 1) var minimum_spacing_cells: int = 1
@export_range(0, 16, 1) var clearance_cells: int = 0
@export_range(0, 10000, 1) var maximum_count: int = 0
@export var blocking: bool = false
@export_range(0, 4, 1) var blocking_radius_cells: int = 0
@export_range(0.0, 1.0, 0.01) var minimum_elevation: float = 0.0
@export_range(0.0, 1.0, 0.01) var maximum_elevation: float = 1.0
@export_range(0.0, 1.0, 0.01) var minimum_moisture: float = 0.0
@export_range(0.0, 1.0, 0.01) var maximum_moisture: float = 1.0
@export_range(0.0, 1.0, 0.01) var minimum_fertility: float = 0.0
@export_range(0.0, 1.0, 0.01) var maximum_fertility: float = 1.0
@export_range(0.0, 1.0, 0.01) var minimum_spirit: float = 0.0
@export_range(0.0, 1.0, 0.01) var maximum_spirit: float = 1.0


func allows(
	terrain_tag: StringName,
	elevation: float,
	moisture: float,
	fertility: float,
	spirit: float
) -> bool:
	return (
		(allowed_terrain_tags.is_empty() or terrain_tag in allowed_terrain_tags)
		and elevation >= minimum_elevation
		and elevation <= maximum_elevation
		and moisture >= minimum_moisture
		and moisture <= maximum_moisture
		and fertility >= minimum_fertility
		and fertility <= maximum_fertility
		and spirit >= minimum_spirit
		and spirit <= maximum_spirit
	)
