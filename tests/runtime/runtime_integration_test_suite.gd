class_name RuntimeIntegrationTestSuite
extends RefCounted

var _scene_tree: SceneTree
var _failures: PackedStringArray = []
var _scene_stack_result: Variant
var _scene_stack_result_received: bool = false


func run(scene_tree: SceneTree) -> PackedStringArray:
	_scene_tree = scene_tree
	await _test_scene_stack()
	_failures.append_array(await GameRootMenuIntegrationTestSuite.new().run(scene_tree))
	_failures.append_array(await MapBattleStoryIntegrationTestSuite.new().run(scene_tree))
	_failures.append_array(await MapExplorationPointerIntegrationTestSuite.new().run(scene_tree))
	_failures.append_array(await MapCombatPresentationIntegrationTestSuite.new().run(scene_tree))
	_failures.append_array(await LanternMapIntegrationTestSuite.new().run(scene_tree))
	return _failures


func _test_scene_stack() -> void:
	var stack := GameSceneStack.new()
	_scene_tree.root.add_child(stack)
	stack.configure(func() -> GameSceneContext: return GameSceneContext.new())
	var fixture := _pack_scene_stack_fixture()
	_expect(stack.reset(fixture, {"name": "root"}), "scene stack should reset")
	var root_scene := stack.current_scene() as SceneStackTestScene
	_capture_scene_stack_result(stack, fixture)
	await _scene_tree.process_frame
	_expect(stack.scene_count() == 2, "scene stack should push a modal scene")
	_expect(root_scene.pause_count == 1, "push should pause the map")
	stack.pop({"closed": true})
	await _scene_tree.process_frame
	_expect(_scene_stack_result_received, "pop should resume the awaiting caller")
	_expect(_scene_stack_result == {"closed": true}, "pop should return its result")
	_expect(root_scene.resume_count == 1, "pop should resume the map")
	stack.queue_free()
	await _scene_tree.process_frame


func _capture_scene_stack_result(stack: GameSceneStack, scene: PackedScene) -> void:
	_scene_stack_result_received = false
	_scene_stack_result = await stack.push(scene, {"name": "modal"})
	_scene_stack_result_received = true


func _pack_scene_stack_fixture() -> PackedScene:
	var instance := SceneStackTestScene.new()
	var packed := PackedScene.new()
	var error := packed.pack(instance)
	instance.free()
	_expect(error == OK, "SceneStack fixture should pack")
	return packed


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
