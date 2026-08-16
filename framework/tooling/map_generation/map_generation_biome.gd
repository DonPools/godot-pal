@tool
class_name MapGenerationBiome
extends Resource

@export var id: StringName
@export var tile_set: TileSet
@export var road_tile: MapGenerationTile
@export var road_terrain_tag: StringName = &"road"
@export var clearing_tile: MapGenerationTile
@export var clearing_terrain_tag: StringName = &"grass"
@export var terrain_rules: Array[MapGenerationTerrainRule] = []
@export var detail_rules: Array[MapGenerationDetailRule] = []
@export var prop_rules: Array[MapGenerationPropRule] = []
