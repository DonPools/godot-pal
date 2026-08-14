class_name GameScene
extends Node

var scene_context: GameSceneContext


func enter(context: GameSceneContext, _arguments: Variant) -> void:
	scene_context = context


func pause_scene() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED


func resume_scene(_result: Variant = null) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT


func exit_scene() -> void:
	pass
