class_name SceneStackTestScene
extends GameScene

var enter_arguments: Variant
var pause_count: int = 0
var resume_count: int = 0
var exit_count: int = 0
var input_count: int = 0
var process_count: int = 0
var resume_result: Variant
var reentrant_replace_accepted: bool = true


func enter(context: GameSceneContext, arguments: Variant) -> void:
	super.enter(context, arguments)
	enter_arguments = arguments
	if arguments is Dictionary and arguments.has("reentrant_scene"):
		reentrant_replace_accepted = context.scene_stack.replace(arguments["reentrant_scene"])


func pause_scene() -> void:
	pause_count += 1
	super.pause_scene()


func resume_scene(result: Variant = null) -> void:
	resume_count += 1
	resume_result = result
	super.resume_scene(result)


func exit_scene() -> void:
	exit_count += 1


func _process(_delta: float) -> void:
	process_count += 1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"scene_stack_test_input"):
		input_count += 1
