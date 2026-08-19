@tool
class_name MapGenerationDetailRule
extends Resource

@export var id: StringName
@export var allowed_terrain_tags: Array[StringName] = []
@export_range(0.0, 1.0, 0.001) var density: float = 0.08
@export_range(0, 16, 1) var minimum_spacing_cells: int = 0
@export_range(0, 10000, 1) var maximum_count: int = 0


func allows(terrain_tag: StringName) -> bool:
	return allowed_terrain_tags.is_empty() or terrain_tag in allowed_terrain_tags
