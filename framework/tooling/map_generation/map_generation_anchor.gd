@tool
class_name MapGenerationAnchor
extends Resource

enum Kind {
	SPAWN,
	PORTAL,
	STORY_CLEARING,
	RESOURCE,
	LANDMARK,
	ROUTE_ENDPOINT,
}

@export var id: StringName
@export var kind: Kind = Kind.LANDMARK
@export var node_path: NodePath
@export var fallback_cell: Vector2i = Vector2i.ZERO
@export var use_scene_node: bool = true
@export_range(0, 16, 1) var clearance_cells: int = 1
@export var must_be_walkable: bool = true
@export var connect_to_road: bool = false
@export var road_entry_direction: Vector2i = Vector2i.ZERO
@export var protected: bool = true
