class_name GameSceneStack
extends Node

signal active_scene_changed(scene: GameScene)
signal scene_closed(scene: GameScene, result: Variant)
signal transition_rejected(reason: String)

var _stack: Array[GameScene] = []
var _context_factory: Callable
var _transitioning: bool = false


func configure(context_factory: Callable) -> void:
	_context_factory = context_factory


func current_scene() -> GameScene:
	return _stack.back() if not _stack.is_empty() else null


func scene_count() -> int:
	return _stack.size()


func is_transitioning() -> bool:
	return _transitioning


func reset(scene: PackedScene, arguments: Variant = null) -> bool:
	if not _begin_transition():
		return false
	var instance := _prepare_scene(scene)
	var context := _create_context()
	if instance == null or context == null:
		if instance != null:
			instance.free()
		_end_transition(null)
		return false
	var closed_scenes: Array[GameScene] = []
	while not _stack.is_empty():
		closed_scenes.append(_take_top_scene())
	_activate_scene(instance, context, arguments)
	_end_transition(instance)
	for closed_scene: GameScene in closed_scenes:
		scene_closed.emit(closed_scene, null)
	return true


func replace(scene: PackedScene, arguments: Variant = null) -> bool:
	if not _begin_transition():
		return false
	var instance := _prepare_scene(scene)
	var context := _create_context()
	if instance == null or context == null:
		if instance != null:
			instance.free()
		_end_transition(null)
		return false
	var closed_scene: GameScene
	if not _stack.is_empty():
		closed_scene = _take_top_scene()
	_activate_scene(instance, context, arguments)
	_end_transition(instance)
	if closed_scene != null:
		scene_closed.emit(closed_scene, null)
	return true


func push(scene: PackedScene, arguments: Variant = null) -> Variant:
	if not _begin_transition():
		return null
	var instance := _prepare_scene(scene)
	var context := _create_context()
	if instance == null or context == null:
		if instance != null:
			instance.free()
		_end_transition(null)
		return null
	var current := current_scene()
	if current != null:
		current.pause_scene()
	_activate_scene(instance, context, arguments)
	_end_transition(instance)
	return await _wait_for_scene_result(instance)


func pop(result: Variant = null) -> bool:
	if _stack.size() < 2:
		_reject_transition("GameSceneStack cannot pop its root scene")
		return false
	if not _begin_transition():
		return false
	var closed_scene := _take_top_scene()
	var current := current_scene()
	current.resume_scene(result)
	_end_transition(current)
	scene_closed.emit(closed_scene, result)
	return true


func _begin_transition() -> bool:
	if _transitioning:
		_reject_transition("GameSceneStack rejected a reentrant transition")
		return false
	_transitioning = true
	return true


func _prepare_scene(scene: PackedScene) -> GameScene:
	if scene == null or not scene.can_instantiate():
		_reject_transition("GameSceneStack cannot instantiate an empty PackedScene")
		return null
	var node := scene.instantiate()
	if not node is GameScene:
		_reject_transition("PackedScene root must inherit GameScene")
		node.free()
		return null
	return node as GameScene


func _create_context() -> GameSceneContext:
	if not _context_factory.is_valid():
		_reject_transition("GameSceneStack requires a valid context factory")
		return null
	var context := _context_factory.call() as GameSceneContext
	if context == null:
		_reject_transition("GameSceneStack context factory returned no GameSceneContext")
	return context


func _activate_scene(
	instance: GameScene,
	context: GameSceneContext,
	arguments: Variant
) -> void:
	add_child(instance)
	_stack.append(instance)
	instance.enter(context, arguments)


func _take_top_scene() -> GameScene:
	var old_scene: GameScene = _stack.pop_back()
	old_scene.exit_scene()
	old_scene.queue_free()
	return old_scene


func _wait_for_scene_result(target: GameScene) -> Variant:
	while true:
		var closed: Variant = await scene_closed
		if closed is Array and closed.size() == 2 and closed[0] == target:
			return closed[1]
	return null


func _end_transition(scene: GameScene) -> void:
	_transitioning = false
	if scene != null:
		active_scene_changed.emit(scene)


func _reject_transition(reason: String) -> void:
	if get_signal_connection_list(&"transition_rejected").is_empty():
		push_error(reason)
	transition_rejected.emit(reason)
