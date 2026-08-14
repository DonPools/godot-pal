class_name HarvestPatch
extends WorldProp

@export var harvested_texture: Texture2D
@export var first_trip_harvested_flag_id: StringName
@export var second_trip_harvested_flag_id: StringName
@export var second_trip_started_flag_id: StringName

@onready var interactable: Interactable = $Interactable

var _game_run: GameRun


func configure(game_run: GameRun = null, map_id: StringName = &"") -> void:
	super.configure(game_run, map_id)
	_game_run = game_run
	refresh()


func refresh() -> void:
	if _game_run == null:
		return
	var second_trip := _game_run.flags.is_set(second_trip_started_flag_id)
	var harvested_flag := (
		second_trip_harvested_flag_id
		if second_trip
		else first_trip_harvested_flag_id
	)
	var harvested := _game_run.flags.is_set(harvested_flag)
	visual.texture = harvested_texture if harvested else texture
	if visual.texture != null:
		visual.position.y = -float(visual.texture.get_height()) * 0.5
	interactable.process_mode = (
		Node.PROCESS_MODE_DISABLED if harvested else Node.PROCESS_MODE_INHERIT
	)
