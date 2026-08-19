@tool
class_name MapGenerationBiome
extends Resource

@export var id: StringName
@export var road_terrain_tag: StringName = &"road"
@export var clearing_terrain_tag: StringName = &"grass"
@export var terrain_rules: Array[MapGenerationTerrainRule] = []
@export var detail_rules: Array[MapGenerationDetailRule] = []
@export var prop_rules: Array[MapGenerationPropRule] = []
@export var terrain_modules: Array[MapGenerationModule3D] = []
@export var detail_modules: Array[MapGenerationModule3D] = []
@export var road_overlay_module: MapGenerationModule3D


func terrain_module(terrain_tag: StringName) -> MapGenerationModule3D:
	for module: MapGenerationModule3D in terrain_modules:
		if module != null and module.id == terrain_tag:
			return module
	return null


func detail_module(rule_id: StringName) -> MapGenerationModule3D:
	for module: MapGenerationModule3D in detail_modules:
		if module != null and module.id == rule_id:
			return module
	return null
