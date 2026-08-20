class_name HarvestPatch3D
extends WorldStateView3D

@export var first_trip_flag: StringName
@export var second_trip_flag: StringName
@export var uprooted_flag: StringName

@onready var full_visual: Node3D = $FullVisual
@onready var cut_visual: Node3D = $CutVisual
@onready var interactable: StoryInteractable3D = $Interactable

var _game_run: GameRun
var _map_id: StringName


func configure_world_state(game_run: GameRun, map_id: StringName) -> void:
	_game_run = game_run
	_map_id = map_id
	refresh_world_state()


func refresh_world_state() -> void:
	if _game_run == null:
		return
	if (
		_game_run.world.is_completed(_map_id, interactable.persistent_id)
		or _game_run.flags.is_set(uprooted_flag)
	):
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	var second_trip_started := _game_run.flags.is_set(
		RoadsideGatheringStory.SECOND_TRIP_STARTED
	)
	var harvested := _game_run.flags.is_set(
		second_trip_flag if second_trip_started else first_trip_flag
	)
	full_visual.visible = not harvested
	cut_visual.visible = harvested
	interactable.process_mode = (
		Node.PROCESS_MODE_DISABLED if harvested else Node.PROCESS_MODE_INHERIT
	)
	interactable.set_pointer_enabled(not harvested)
