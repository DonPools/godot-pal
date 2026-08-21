class_name GameSceneContext
extends RefCounted

var game_run: GameRun
var content_database: ContentDatabase
var scene_stack: GameSceneStack
var story_director: StoryDirector
var dialogue_layer: DialogueLayer
var asset_library: AssetLibrary
var audio_service: AudioService
var save_service: SaveService
var settings_service: SettingsService
var menu_scene: PackedScene
var save_load_scene: PackedScene
var settings_scene: PackedScene
var start_new_game: Callable
var install_loaded_run: Callable
var return_to_title: Callable
