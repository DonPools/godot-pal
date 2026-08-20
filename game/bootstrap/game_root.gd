class_name GameRoot
extends Node

const START_MAP_ID := &"map.roadside.lantern_pass"
const DEBUG_SAVE_PATH := "user://roadside_save.json"

@export var content_database: ContentDatabase
@export var story_module: StoryModule
@export var title_scene: PackedScene
@export var menu_scene: PackedScene
@export var shop_scene: PackedScene
@export var save_load_scene: PackedScene
@export var settings_scene: PackedScene

@onready var scene_stack: GameSceneStack = $GameSceneStack
@onready var story_director: StoryDirector = $StoryDirector
@onready var asset_library: AssetLibrary = $AssetLibrary
@onready var audio_service: AudioService = $AudioService
@onready var save_service: SaveService = $SaveService
@onready var settings_service: SettingsService = $SettingsService
@onready var dialogue_layer: DialogueLayer = $OverlayLayer/DialogueLayer
@onready var status_label: Label = $OverlayLayer/StatusLabel

var game_run := GameRun.new()


func _ready() -> void:
	_ensure_input_actions()
	asset_library.initialize()
	audio_service.configure()
	settings_service.configure(audio_service)
	dialogue_layer.configure(audio_service, settings_service)
	var errors := content_database.build_index()
	for error: String in errors:
		push_error(error)
	save_service.configure(content_database)
	save_service.configure_save_allowed_provider(_is_save_allowed)
	story_director.configure(
		_provide_game_run,
		travel_to,
		dialogue_layer,
		scene_stack,
		shop_scene,
		content_database
	)
	scene_stack.configure(_create_scene_context)
	scene_stack.reset(title_scene)


func _exit_tree() -> void:
	if audio_service != null:
		audio_service.shutdown()


func start_new_game() -> void:
	game_run = GameRun.new_game(content_database)
	var start_map := content_database.map(START_MAP_ID)
	game_run.location.map_id = start_map.id
	game_run.location.spawn_id = start_map.default_spawn_id
	game_run.location.has_exact_position = false
	scene_stack.reset(start_map.scene, _map_arguments(start_map, start_map.default_spawn_id))


func travel_to(destination: MapDefinition, spawn_id: StringName) -> void:
	if destination == null:
		push_error("GameRoot.travel_to received no destination")
		return
	game_run.location.map_id = destination.id
	game_run.location.spawn_id = spawn_id
	game_run.location.has_exact_position = false
	scene_stack.replace(destination.scene, _map_arguments(destination, spawn_id))


func _create_scene_context() -> GameSceneContext:
	var context := GameSceneContext.new()
	context.game_run = game_run
	context.content_database = content_database
	context.scene_stack = scene_stack
	context.story_director = story_director
	context.dialogue_layer = dialogue_layer
	context.asset_library = asset_library
	context.audio_service = audio_service
	context.save_service = save_service
	context.settings_service = settings_service
	context.menu_scene = menu_scene
	context.save_load_scene = save_load_scene
	context.settings_scene = settings_scene
	context.start_new_game = start_new_game
	context.install_loaded_run = install_loaded_run
	return context


func _map_arguments(map: MapDefinition, spawn_id: StringName) -> Dictionary:
	return {
		"definition": map,
		"spawn_id": spawn_id,
		"story": map.story_module if map.story_module != null else story_module,
	}


func _provide_game_run() -> GameRun:
	return game_run


func install_loaded_run(loaded: GameRun) -> void:
	if loaded == null:
		_show_status("存档损坏，当前进度未改变")
		return
	var map := content_database.map(loaded.location.map_id)
	if map == null:
		_show_status("存档引用了未知地图")
		return
	game_run = loaded
	scene_stack.reset(map.scene, _map_arguments(map, loaded.location.spawn_id))
	_show_status("已读取存档")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if dialogue_layer.is_active() or story_director.is_busy():
		return
	var active_scene := scene_stack.current_scene()
	if active_scene is MapGameScene and (active_scene as MapGameScene).has_active_battle():
		return
	if event.is_action_pressed(&"menu"):
		if scene_stack.current_scene() is MapGameScene and menu_scene != null:
			(scene_stack.current_scene() as MapGameScene).capture_location()
			scene_stack.push(menu_scene)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"debug_save"):
		var current := scene_stack.current_scene()
		if current is MapGameScene:
			current.capture_location()
		var error := save_service.save_run(game_run, DEBUG_SAVE_PATH)
		_show_status("测试存档已保存" if error == OK else "保存失败：%s" % error_string(error))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"debug_load"):
		install_loaded_run(save_service.load_run(DEBUG_SAVE_PATH))
		get_viewport().set_input_as_handled()


func _is_save_allowed() -> bool:
	var current := scene_stack.current_scene()
	return not (current is MapGameScene and (current as MapGameScene).has_active_battle())


func _toggle_fullscreen() -> void:
	settings_service.toggle_fullscreen()


func _show_status(message: String) -> void:
	status_label.text = message
	status_label.visible = true
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_callback(func() -> void: status_label.visible = false)


func _ensure_input_actions() -> void:
	_copy_action(&"move_north", &"ui_up")
	_copy_action(&"move_south", &"ui_down")
	_copy_action(&"move_west", &"ui_left")
	_copy_action(&"move_east", &"ui_right")
	_copy_action(&"interact", &"ui_accept")
	_add_key_action(&"move_west", KEY_A)
	_add_key_action(&"move_east", KEY_D)
	_add_key_action(&"move_north", KEY_W)
	_add_key_action(&"move_south", KEY_S)
	_add_key_action(&"menu", KEY_M)
	_add_key_action(&"save_menu", KEY_F6)
	_add_key_action(&"toggle_fullscreen", KEY_F11)
	_add_joypad_button(&"interact", JOY_BUTTON_A)
	_add_joypad_button(&"ui_cancel", JOY_BUTTON_B)
	_add_joypad_button(&"menu", JOY_BUTTON_START)
	_add_joypad_axis(&"move_west", JOY_AXIS_LEFT_X, -1.0)
	_add_joypad_axis(&"move_east", JOY_AXIS_LEFT_X, 1.0)
	_add_joypad_axis(&"move_north", JOY_AXIS_LEFT_Y, -1.0)
	_add_joypad_axis(&"move_south", JOY_AXIS_LEFT_Y, 1.0)
	_add_joypad_axis(&"aim_west", JOY_AXIS_RIGHT_X, -1.0)
	_add_joypad_axis(&"aim_east", JOY_AXIS_RIGHT_X, 1.0)
	_add_joypad_axis(&"aim_north", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joypad_axis(&"aim_south", JOY_AXIS_RIGHT_Y, 1.0)
	_add_mouse_button(&"combat_attack", MOUSE_BUTTON_LEFT)
	_add_joypad_button(&"combat_attack", JOY_BUTTON_A)
	_add_mouse_button(&"combat_skill_one", MOUSE_BUTTON_RIGHT)
	_add_joypad_button(&"combat_skill_one", JOY_BUTTON_X)
	_add_key_action(&"combat_skill_two", KEY_1)
	_add_joypad_button(&"combat_skill_two", JOY_BUTTON_Y)
	_add_key_action(&"combat_skill_three", KEY_2)
	_add_joypad_button(&"combat_skill_three", JOY_BUTTON_RIGHT_SHOULDER)
	_add_key_action(&"combat_dodge", KEY_SPACE)
	_add_joypad_button(&"combat_dodge", JOY_BUTTON_B)
	_add_key_action(&"combat_item", KEY_Q)
	_add_joypad_button(&"combat_item", JOY_BUTTON_LEFT_SHOULDER)
	_add_key_action(&"combat_stand_ground", KEY_SHIFT)
	_add_key_action(&"combat_force_move", KEY_CTRL)
	_add_key_action(&"combat_target_next", KEY_TAB)
	_add_joypad_button(&"combat_target_next", JOY_BUTTON_RIGHT_STICK)
	_add_key_action(&"debug_save", KEY_F5)
	_add_key_action(&"debug_load", KEY_F9)


func _copy_action(target: StringName, source: StringName) -> void:
	if not InputMap.has_action(target):
		InputMap.add_action(target)
	for event: InputEvent in InputMap.action_get_events(source):
		if not InputMap.action_has_event(target, event):
			InputMap.action_add_event(target, event)


func _add_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _add_mouse_button(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _add_joypad_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventJoypadButton.new()
	event.button_index = button
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _add_joypad_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)
