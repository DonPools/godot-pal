class_name MapGenerationPlan
extends RefCounted

var generator_version: int
var seed: int
var origin: Vector2i
var size: Vector2i
var elevation: Dictionary[Vector2i, float] = {}
var moisture: Dictionary[Vector2i, float] = {}
var fertility: Dictionary[Vector2i, float] = {}
var spirit: Dictionary[Vector2i, float] = {}
var disturbance: Dictionary[Vector2i, float] = {}
var terrain_tiles: Dictionary[Vector2i, MapGenerationTile] = {}
var terrain_tags: Dictionary[Vector2i, StringName] = {}
var detail_tiles: Dictionary[Vector2i, MapGenerationTile] = {}
var detail_rule_ids: Dictionary[Vector2i, StringName] = {}
var walkable_cells: Dictionary[Vector2i, bool] = {}
var protected_cells: Dictionary[Vector2i, bool] = {}
var road_forbidden_cells: Dictionary[Vector2i, bool] = {}
var road_cells: Dictionary[Vector2i, bool] = {}
var blocked_cells: Dictionary[Vector2i, bool] = {}
var resolved_anchor_cells: Dictionary[StringName, Vector2i] = {}
var prop_placements: Array[MapGenerationPropPlacement] = []
var metrics: Dictionary = {}
var diagnostics: Array[Dictionary] = []
var plan_hash: String = ""


func is_valid() -> bool:
	return diagnostics.is_empty()


func contains_cell(cell: Vector2i) -> bool:
	return Rect2i(origin, size).has_point(cell)


func to_summary(profile_path: String = "") -> Dictionary:
	return {
		"generator_version": generator_version,
		"profile_path": profile_path,
		"seed": seed,
		"plan_hash": plan_hash,
		"origin": {"x": origin.x, "y": origin.y},
		"size": {"x": size.x, "y": size.y},
		"metrics": metrics,
		"diagnostics": diagnostics,
	}
