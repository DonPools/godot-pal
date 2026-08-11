class_name GameSceneStack
extends Node

signal active_scene_changed(scene: GameScene)

var _stack: Array[GameScene] = []
var _context_factory: Callable
var _transitioning: bool = false


func configure(context_factory: Callable) -> void:
	_context_factory = context_factory


func current_scene() -> GameScene:
	return _stack.back() if not _stack.is_empty() else null


func reset(scene: PackedScene, arguments: Variant = null) -> void:
	if not _begin_transition():
		return
	while not _stack.is_empty():
		var old_scene: GameScene = _stack.pop_back()
		old_scene.exit_scene()
		old_scene.queue_free()
	var instance := _instantiate(scene, arguments)
	_end_transition(instance)


func replace(scene: PackedScene, arguments: Variant = null) -> void:
	if not _begin_transition():
		return
	if not _stack.is_empty():
		var old_scene: GameScene = _stack.pop_back()
		old_scene.exit_scene()
		old_scene.queue_free()
	var instance := _instantiate(scene, arguments)
	_end_transition(instance)


func push(scene: PackedScene, arguments: Variant = null) -> void:
	if not _begin_transition():
		return
	var current := current_scene()
	if current != null:
		current.pause_scene()
	var instance := _instantiate(scene, arguments)
	_end_transition(instance)


func pop(result: Variant = null) -> void:
	if not _begin_transition() or _stack.size() < 2:
		_transitioning = false
		return
	var old_scene: GameScene = _stack.pop_back()
	old_scene.exit_scene()
	old_scene.queue_free()
	var current := current_scene()
	current.resume_scene(result)
	_end_transition(current)


func _begin_transition() -> bool:
	if _transitioning:
		push_error("GameSceneStack rejected a reentrant transition")
		return false
	_transitioning = true
	return true


func _instantiate(scene: PackedScene, arguments: Variant) -> GameScene:
	if scene == null:
		push_error("GameSceneStack cannot instantiate an empty PackedScene")
		return null
	var instance := scene.instantiate() as GameScene
	if instance == null:
		push_error("PackedScene root must inherit GameScene")
		return null
	add_child(instance)
	_stack.append(instance)
	var context: GameSceneContext = _context_factory.call()
	instance.enter(context, arguments)
	return instance


func _end_transition(scene: GameScene) -> void:
	_transitioning = false
	if scene != null:
		active_scene_changed.emit(scene)
