class_name MapGenerator
extends RefCounted

const GENERATOR_VERSION := 1
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]


func generate(profile: MapGenerationProfile, map_scene: Node = null) -> MapGenerationPlan:
	# The plan contains no live scene nodes, so CLI, editor preview, and tests share one generator.
	var plan := MapGenerationPlan.new()
	plan.generator_version = GENERATOR_VERSION
	if profile == null:
		plan.diagnostics = MapGenerationValidator.new().validate_profile(null)
		return plan
	plan.seed = profile.seed
	plan.origin = profile.map_origin
	plan.size = profile.map_size
	plan.diagnostics = MapGenerationValidator.new().validate_profile(profile, map_scene)
	if not plan.diagnostics.is_empty():
		return plan
	_resolve_anchors(profile, map_scene, plan)
	_mark_protected_cells(profile, plan)
	_generate_ecology_fields(profile, plan)
	_generate_roads(profile, plan)
	_generate_disturbance(profile, plan)
	_classify_terrain(profile, plan)
	_place_details(profile, plan)
	_place_props(profile, plan)
	_finalize_metrics(profile, plan)
	plan.diagnostics.append_array(MapGenerationValidator.new().validate_plan(profile, plan))
	plan.plan_hash = _plan_hash(profile, plan)
	return plan


func _resolve_anchors(
	profile: MapGenerationProfile,
	map_scene: Node,
	plan: MapGenerationPlan
) -> void:
	var ground_layer := (
		map_scene.get_node_or_null(^"GroundLayer") as TileMapLayer
		if map_scene != null
		else null
	)
	for anchor: MapGenerationAnchor in profile.anchors:
		var cell := anchor.fallback_cell
		if anchor.use_scene_node and map_scene != null and ground_layer != null:
			var anchor_node := map_scene.get_node_or_null(anchor.node_path) as Node2D
			if anchor_node != null:
				cell = ground_layer.local_to_map(ground_layer.to_local(anchor_node.global_position))
		plan.resolved_anchor_cells[anchor.id] = cell


func _mark_protected_cells(profile: MapGenerationProfile, plan: MapGenerationPlan) -> void:
	for anchor: MapGenerationAnchor in profile.anchors:
		if not anchor.protected:
			continue
		var centre: Vector2i = plan.resolved_anchor_cells[anchor.id]
		for offset_y: int in range(-anchor.clearance_cells, anchor.clearance_cells + 1):
			for offset_x: int in range(-anchor.clearance_cells, anchor.clearance_cells + 1):
				var cell := centre + Vector2i(offset_x, offset_y)
				if plan.contains_cell(cell):
					plan.protected_cells[cell] = true
					if not anchor.connect_to_road:
						plan.road_forbidden_cells[cell] = true


func _generate_ecology_fields(profile: MapGenerationProfile, plan: MapGenerationPlan) -> void:
	var elevation_noise := _noise(profile.seed, 101, profile.elevation_frequency)
	var moisture_noise := _noise(profile.seed, 211, profile.moisture_frequency)
	var fertility_noise := _noise(profile.seed, 307, profile.fertility_frequency)
	var spirit_noise := _noise(profile.seed, 401, profile.spirit_frequency)
	for cell: Vector2i in _cells(plan):
		plan.elevation[cell] = _sample(elevation_noise, cell)
		plan.moisture[cell] = _sample(moisture_noise, cell)
		plan.fertility[cell] = clampf(
			_sample(fertility_noise, cell) * 0.65 + plan.moisture[cell] * 0.35,
			0.0,
			1.0
		)
		plan.spirit[cell] = _sample(spirit_noise, cell)


func _generate_roads(profile: MapGenerationProfile, plan: MapGenerationPlan) -> void:
	var anchors: Array[MapGenerationAnchor] = []
	for anchor: MapGenerationAnchor in profile.anchors:
		if anchor.connect_to_road:
			anchors.append(anchor)
	anchors.sort_custom(func(left: MapGenerationAnchor, right: MapGenerationAnchor) -> bool:
		return String(left.id) < String(right.id)
	)
	if anchors.is_empty():
		return
	var connected: Dictionary[StringName, bool] = {anchors[0].id: true}
	# A deterministic Prim-style connection order gives global routes before per-edge A*.
	while connected.size() < anchors.size():
		var best_from: MapGenerationAnchor
		var best_to: MapGenerationAnchor
		var best_distance := 1_000_000
		var best_key := ""
		for from_anchor: MapGenerationAnchor in anchors:
			if not connected.has(from_anchor.id):
				continue
			for to_anchor: MapGenerationAnchor in anchors:
				if connected.has(to_anchor.id):
					continue
				var from_cell: Vector2i = plan.resolved_anchor_cells[from_anchor.id]
				var to_cell: Vector2i = plan.resolved_anchor_cells[to_anchor.id]
				var distance := absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
				var key := "%s:%s" % [from_anchor.id, to_anchor.id]
				if distance < best_distance or (distance == best_distance and key < best_key):
					best_from = from_anchor
					best_to = to_anchor
					best_distance = distance
					best_key = key
		if best_from == null or best_to == null:
			break
		var from_cell: Vector2i = plan.resolved_anchor_cells[best_from.id]
		var to_cell: Vector2i = plan.resolved_anchor_cells[best_to.id]
		var from_approach := from_cell + best_from.road_entry_direction
		var to_approach := to_cell + best_to.road_entry_direction
		var path := _road_path(
			plan,
			from_approach,
			to_approach
		)
		if path.is_empty():
			plan.diagnostics.append(_diagnostic(
				"map_generation_road_path_missing",
				"could not connect road anchors %s and %s" % [best_from.id, best_to.id],
				profile.authoring_source_path(),
				"anchors",
				"%s:%s" % [best_from.id, best_to.id]
			))
			break
		path.push_front(from_cell)
		path.append(to_cell)
		for path_cell: Vector2i in path:
			_mark_road_width(path_cell, profile.road_width_cells, plan)
		connected[best_to.id] = true


func _road_path(plan: MapGenerationPlan, from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(plan.origin, plan.size)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	for cell: Vector2i in _cells(plan):
		var weight := 1.0 + plan.moisture[cell] * 1.4 + plan.elevation[cell] * 0.8
		grid.set_point_weight_scale(cell, weight)
		if plan.road_forbidden_cells.has(cell):
			grid.set_point_solid(cell, true)
	var raw_path: Array[Vector2i] = grid.get_id_path(from_cell, to_cell)
	return raw_path


func _mark_road_width(cell: Vector2i, width: int, plan: MapGenerationPlan) -> void:
	var radius := maxi(width - 1, 0)
	for offset_y: int in range(-radius, radius + 1):
		for offset_x: int in range(-radius, radius + 1):
			if absi(offset_x) + absi(offset_y) > radius:
				continue
			var road_cell := cell + Vector2i(offset_x, offset_y)
			if plan.contains_cell(road_cell):
				plan.road_cells[road_cell] = true


func _generate_disturbance(profile: MapGenerationProfile, plan: MapGenerationPlan) -> void:
	var base_noise := _noise(profile.seed, 509, 0.035)
	var road_cells: Array[Vector2i] = []
	road_cells.assign(plan.road_cells.keys())
	for cell: Vector2i in _cells(plan):
		var distance := 12
		for road_cell: Vector2i in road_cells:
			distance = mini(distance, absi(cell.x - road_cell.x) + absi(cell.y - road_cell.y))
			if distance == 0:
				break
		var road_disturbance := clampf(1.0 - float(distance) / 7.0, 0.0, 1.0)
		plan.disturbance[cell] = maxf(_sample(base_noise, cell) * 0.3, road_disturbance)


func _classify_terrain(profile: MapGenerationProfile, plan: MapGenerationPlan) -> void:
	for cell: Vector2i in _cells(plan):
		if plan.road_cells.has(cell):
			plan.terrain_tiles[cell] = profile.biome.road_tile
			plan.terrain_tags[cell] = profile.biome.road_terrain_tag
			plan.walkable_cells[cell] = true
			continue
		if plan.protected_cells.has(cell):
			plan.terrain_tiles[cell] = profile.biome.clearing_tile
			plan.terrain_tags[cell] = profile.biome.clearing_terrain_tag
			plan.walkable_cells[cell] = true
			continue
		var rule := _matching_terrain_rule(profile.biome.terrain_rules, cell, plan)
		if rule == null:
			plan.diagnostics.append(_diagnostic(
				"map_generation_terrain_unmatched",
				"no terrain rule matches cell %s" % cell,
				profile.authoring_source_path(),
				"biome.terrain_rules",
				"%d,%d" % [cell.x, cell.y]
			))
			continue
		plan.terrain_tiles[cell] = rule.tile
		plan.terrain_tags[cell] = rule.terrain_tag
		plan.walkable_cells[cell] = rule.walkable


func _matching_terrain_rule(
	rules: Array[MapGenerationTerrainRule],
	cell: Vector2i,
	plan: MapGenerationPlan
) -> MapGenerationTerrainRule:
	for rule: MapGenerationTerrainRule in rules:
		if rule != null and rule.matches(
			plan.elevation[cell],
			plan.moisture[cell],
			plan.fertility[cell],
			plan.spirit[cell],
			plan.disturbance[cell]
		):
			return rule
	return null


func _place_details(profile: MapGenerationProfile, plan: MapGenerationPlan) -> void:
	var rules: Array[MapGenerationDetailRule] = profile.biome.detail_rules.duplicate()
	rules.sort_custom(func(left: MapGenerationDetailRule, right: MapGenerationDetailRule) -> bool:
		return String(left.id) < String(right.id)
	)
	for rule_index: int in rules.size():
		var rule: MapGenerationDetailRule = rules[rule_index]
		var rng := RandomNumberGenerator.new()
		rng.seed = _derived_seed(profile.seed, 701 + rule_index * 83)
		var rule_cells: Array[Vector2i] = []
		for cell: Vector2i in _cells(plan):
			if rule.maximum_count > 0 and rule_cells.size() >= rule.maximum_count:
				break
			if plan.detail_tiles.has(cell) or plan.road_cells.has(cell) or plan.protected_cells.has(cell):
				continue
			if rng.randf() > rule.density:
				continue
			if not rule.allows(plan.terrain_tags.get(cell, &"")):
				continue
			if _too_close_to_cells(cell, rule_cells, rule.minimum_spacing_cells):
				continue
			plan.detail_tiles[cell] = rule.tile
			rule_cells.append(cell)


func _place_props(profile: MapGenerationProfile, plan: MapGenerationPlan) -> void:
	var rules: Array[MapGenerationPropRule] = profile.biome.prop_rules.duplicate()
	rules.sort_custom(func(left: MapGenerationPropRule, right: MapGenerationPropRule) -> bool:
		return String(left.id) < String(right.id)
	)
	var placement_count := 0
	var occupied_cells: Dictionary[Vector2i, bool] = {}
	for rule_index: int in rules.size():
		var rule: MapGenerationPropRule = rules[rule_index]
		var rng := RandomNumberGenerator.new()
		rng.seed = _derived_seed(profile.seed, 1009 + rule_index * 97)
		var rule_cells: Array[Vector2i] = []
		for cell: Vector2i in _cells(plan):
			if placement_count >= profile.maximum_generated_props:
				return
			if rule.maximum_count > 0 and rule_cells.size() >= rule.maximum_count:
				break
			if rng.randf() > rule.density:
				continue
			if plan.protected_cells.has(cell) or plan.road_cells.has(cell) or occupied_cells.has(cell):
				continue
			var terrain_tag: StringName = plan.terrain_tags.get(cell, &"")
			if not rule.allows(
				terrain_tag,
				plan.elevation[cell],
				plan.moisture[cell],
				plan.fertility[cell],
				plan.spirit[cell]
			):
				continue
			if _too_close_to_cells(cell, rule_cells, rule.minimum_spacing_cells):
				continue
			if _too_close_to_protected(cell, plan, rule.clearance_cells):
				continue
			var blocking_footprint := _blocking_footprint(cell, rule.blocking_radius_cells, plan)
			# Large rocks and logs reserve logical neighbors even though they remain one scene node.
			if rule.blocking and _footprint_is_forbidden(blocking_footprint, plan):
				continue
			var placement := MapGenerationPropPlacement.new()
			placement.id = StringName("generated.%s.%d_%d" % [rule.id, cell.x, cell.y])
			placement.rule = rule
			placement.cell = cell
			plan.prop_placements.append(placement)
			rule_cells.append(cell)
			placement_count += 1
			occupied_cells[cell] = true
			if rule.blocking:
				for blocked_cell: Vector2i in blocking_footprint:
					plan.blocked_cells[blocked_cell] = true


func _too_close_to_cells(cell: Vector2i, cells: Array[Vector2i], spacing: int) -> bool:
	for other: Vector2i in cells:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) <= spacing:
			return true
	return false


func _too_close_to_protected(cell: Vector2i, plan: MapGenerationPlan, clearance: int) -> bool:
	if clearance <= 0:
		return false
	for protected_cell: Vector2i in plan.protected_cells:
		if maxi(absi(cell.x - protected_cell.x), absi(cell.y - protected_cell.y)) <= clearance:
			return true
	return false


func _blocking_footprint(
	cell: Vector2i,
	radius: int,
	plan: MapGenerationPlan
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset_y: int in range(-radius, radius + 1):
		for offset_x: int in range(-radius, radius + 1):
			var footprint_cell := cell + Vector2i(offset_x, offset_y)
			if plan.contains_cell(footprint_cell):
				result.append(footprint_cell)
	return result


func _footprint_is_forbidden(footprint: Array[Vector2i], plan: MapGenerationPlan) -> bool:
	for cell: Vector2i in footprint:
		if (
			plan.road_cells.has(cell)
			or plan.protected_cells.has(cell)
			or plan.blocked_cells.has(cell)
		):
			return true
	return false


func _finalize_metrics(profile: MapGenerationProfile, plan: MapGenerationPlan) -> void:
	var habitat_counts: Dictionary[String, int] = {}
	for tag: StringName in plan.terrain_tags.values():
		var key := String(tag)
		habitat_counts[key] = habitat_counts.get(key, 0) + 1
	var total_cells := profile.map_size.x * profile.map_size.y
	var habitat_ratios: Dictionary[String, float] = {}
	for tag: String in habitat_counts:
		habitat_ratios[tag] = float(habitat_counts[tag]) / float(total_cells)
	var anchor_cells: Dictionary[String, Dictionary] = {}
	for anchor_id: StringName in plan.resolved_anchor_cells:
		var anchor_cell: Vector2i = plan.resolved_anchor_cells[anchor_id]
		anchor_cells[String(anchor_id)] = {"x": anchor_cell.x, "y": anchor_cell.y}
	var anchor_distances := _anchor_distances(profile, plan)
	var reach_start := plan.origin
	for anchor: MapGenerationAnchor in profile.anchors:
		if anchor != null and anchor.must_be_walkable:
			reach_start = plan.resolved_anchor_cells[anchor.id]
			break
	var reachability := _walkable_distances(plan, reach_start)
	var walkable_cell_count := 0
	for cell: Vector2i in plan.walkable_cells:
		if plan.walkable_cells[cell] and not plan.blocked_cells.get(cell, false):
			walkable_cell_count += 1
	plan.metrics = {
		"cell_count": total_cells,
		"road_cell_count": plan.road_cells.size(),
		"protected_cell_count": plan.protected_cells.size(),
		"prop_count": plan.prop_placements.size(),
		"detail_cell_count": plan.detail_tiles.size(),
		"blocking_prop_count": plan.blocked_cells.size(),
		"habitat_counts": habitat_counts,
		"habitat_ratios": habitat_ratios,
		"anchor_count": plan.resolved_anchor_cells.size(),
		"anchor_cells": anchor_cells,
		"anchor_distances": anchor_distances,
		"reachable_walkable_cell_count": reachability.size(),
		"unreachable_walkable_cell_count": maxi(walkable_cell_count - reachability.size(), 0),
	}


func _anchor_distances(profile: MapGenerationProfile, plan: MapGenerationPlan) -> Dictionary[String, int]:
	var result: Dictionary[String, int] = {}
	var anchors: Array[MapGenerationAnchor] = []
	for anchor: MapGenerationAnchor in profile.anchors:
		if anchor != null and anchor.must_be_walkable:
			anchors.append(anchor)
	anchors.sort_custom(func(left: MapGenerationAnchor, right: MapGenerationAnchor) -> bool:
		return String(left.id) < String(right.id)
	)
	for from_index: int in anchors.size():
		var from_anchor := anchors[from_index]
		var distances := _walkable_distances(plan, plan.resolved_anchor_cells[from_anchor.id])
		for to_index: int in range(from_index + 1, anchors.size()):
			var to_anchor := anchors[to_index]
			var to_cell: Vector2i = plan.resolved_anchor_cells[to_anchor.id]
			result["%s:%s" % [from_anchor.id, to_anchor.id]] = int(distances.get(to_cell, -1))
	return result


func _walkable_distances(plan: MapGenerationPlan, start: Vector2i) -> Dictionary[Vector2i, int]:
	var result: Dictionary[Vector2i, int] = {}
	if not plan.walkable_cells.get(start, false) or plan.blocked_cells.get(start, false):
		return result
	var queue: Array[Vector2i] = [start]
	result[start] = 0
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		for direction: Vector2i in DIRECTIONS:
			var neighbor := current + direction
			if (
				plan.contains_cell(neighbor)
				and plan.walkable_cells.get(neighbor, false)
				and not plan.blocked_cells.get(neighbor, false)
				and not result.has(neighbor)
			):
				result[neighbor] = result[current] + 1
				queue.append(neighbor)
	return result


func _plan_hash(profile: MapGenerationProfile, plan: MapGenerationPlan) -> String:
	var cells: Array[Dictionary] = []
	for cell: Vector2i in _cells(plan):
		var tile: MapGenerationTile = plan.terrain_tiles.get(cell)
		var detail_tile: MapGenerationTile = plan.detail_tiles.get(cell)
		cells.append({
			"x": cell.x,
			"y": cell.y,
			"tag": String(plan.terrain_tags.get(cell, &"")),
			"tile": tile.to_dictionary() if tile != null else {},
			"detail": detail_tile.to_dictionary() if detail_tile != null else {},
			"road": plan.road_cells.has(cell),
		})
	var props: Array[Dictionary] = []
	for placement: MapGenerationPropPlacement in plan.prop_placements:
		props.append(placement.to_dictionary())
	var payload := JSON.stringify({
		"generator_version": GENERATOR_VERSION,
		"profile_schema": profile.schema_version,
		"seed": plan.seed,
		"origin": [plan.origin.x, plan.origin.y],
		"size": [plan.size.x, plan.size.y],
		"cells": cells,
		"props": props,
	}, "", true, true)
	return payload.sha256_text()


func _noise(seed: int, salt: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = _derived_seed(seed, salt)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	return noise


func _sample(noise: FastNoiseLite, cell: Vector2i) -> float:
	return clampf((noise.get_noise_2d(cell.x, cell.y) + 1.0) * 0.5, 0.0, 1.0)


func _derived_seed(seed: int, salt: int) -> int:
	var value := absi(seed * 1_103_515_245 + salt * 97_531 + 12_345)
	return value % 2_147_483_647


func _cells(plan: MapGenerationPlan) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.resize(plan.size.x * plan.size.y)
	var index := 0
	for y: int in range(plan.origin.y, plan.origin.y + plan.size.y):
		for x: int in range(plan.origin.x, plan.origin.x + plan.size.x):
			result[index] = Vector2i(x, y)
			index += 1
	return result


func _diagnostic(
	code: String,
	message: String,
	file: String,
	field: String,
	id: String = ""
) -> Dictionary:
	return {"code": code, "message": message, "file": file, "field": field, "id": id}
