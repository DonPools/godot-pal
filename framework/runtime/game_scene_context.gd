class_name GameSceneContext
extends RefCounted

var game_run: GameRun
var content_database: ContentDatabase
var scene_stack: GameSceneStack
var story_director: StoryDirector
var dialogue_layer: DialogueLayer
var startup_diagnostic: String
var startup_diagnostics: Array[Dictionary] = []
var audio_service: AudioService
var save_service: SaveService
var settings_service: SettingsService
var menu_scene: PackedScene
var save_load_scene: PackedScene
var settings_scene: PackedScene

var _start_new_game_action: Callable
var _install_loaded_game_run_action: Callable
var _return_to_title_action: Callable


func configure_application_actions(
	start_new_game_action: Callable,
	install_loaded_game_run_action: Callable,
	return_to_title_action: Callable
) -> void:
	_start_new_game_action = start_new_game_action
	_install_loaded_game_run_action = install_loaded_game_run_action
	_return_to_title_action = return_to_title_action


func request_new_game() -> void:
	if not _start_new_game_action.is_valid():
		push_error("GameSceneContext has no new-game action")
		return
	_start_new_game_action.call()


func install_loaded_game_run(loaded_game_run: GameRun) -> void:
	if not _install_loaded_game_run_action.is_valid():
		push_error("GameSceneContext has no loaded-run installation action")
		return
	_install_loaded_game_run_action.call(loaded_game_run)


func request_return_to_title() -> void:
	if not _return_to_title_action.is_valid():
		push_error("GameSceneContext has no return-to-title action")
		return
	_return_to_title_action.call()
