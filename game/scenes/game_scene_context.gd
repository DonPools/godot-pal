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
var menu_scene: PackedScene
var start_new_game: Callable
var install_loaded_run: Callable
