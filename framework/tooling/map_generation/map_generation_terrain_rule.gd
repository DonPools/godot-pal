@tool
class_name MapGenerationTerrainRule
extends Resource

@export var id: StringName
@export var terrain_tag: StringName
@export var tile: MapGenerationTile
@export var walkable: bool = true
@export_range(0.0, 1.0, 0.01) var minimum_elevation: float = 0.0
@export_range(0.0, 1.0, 0.01) var maximum_elevation: float = 1.0
@export_range(0.0, 1.0, 0.01) var minimum_moisture: float = 0.0
@export_range(0.0, 1.0, 0.01) var maximum_moisture: float = 1.0
@export_range(0.0, 1.0, 0.01) var minimum_fertility: float = 0.0
@export_range(0.0, 1.0, 0.01) var maximum_fertility: float = 1.0
@export_range(0.0, 1.0, 0.01) var minimum_spirit: float = 0.0
@export_range(0.0, 1.0, 0.01) var maximum_spirit: float = 1.0
@export_range(0.0, 1.0, 0.01) var minimum_disturbance: float = 0.0
@export_range(0.0, 1.0, 0.01) var maximum_disturbance: float = 1.0


func matches(
	elevation: float,
	moisture: float,
	fertility: float,
	spirit: float,
	disturbance: float
) -> bool:
	return (
		elevation >= minimum_elevation
		and elevation <= maximum_elevation
		and moisture >= minimum_moisture
		and moisture <= maximum_moisture
		and fertility >= minimum_fertility
		and fertility <= maximum_fertility
		and spirit >= minimum_spirit
		and spirit <= maximum_spirit
		and disturbance >= minimum_disturbance
		and disturbance <= maximum_disturbance
	)
