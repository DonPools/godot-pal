extends SceneTree

const TEST_SAVE := "res://tests/.tmp_roadside_save.json"
const TEST_SLOTS := "res://tests/.tmp_roadside_slots"
const TEST_SETTINGS := "res://tests/.tmp_roadside_settings.cfg"

var _failures: PackedStringArray = []
var _scene_stack_result: Variant
var _scene_stack_result_received: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_ensure_input_actions()
	_test_display_baseline()
	_test_content_database()
	_test_original_assets()
	_test_directional_frames()
	await _test_roadside_scene()
	_test_game_run_round_trip()
	_test_save_service()
	_test_settings_service()
	await _test_scene_stack()
	await _test_game_root_smoke()
	if _failures.is_empty():
		print("roadside slice tests passed")
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)


func _test_display_baseline() -> void:
	var viewport_width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var viewport_height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	var window_width := int(ProjectSettings.get_setting("display/window/size/window_width_override", 0))
	var window_height := int(ProjectSettings.get_setting("display/window/size/window_height_override", 0))
	_expect(
		viewport_width == 320 and viewport_height == 180,
		"formal slice should use a 320x180 internal viewport, got %dx%d"
		% [viewport_width, viewport_height]
	)
	_expect(
		window_width == 960 and window_height == 540,
		"default window should be an exact 3x presentation, got %dx%d"
		% [window_width, window_height]
	)
	_expect(
		ProjectSettings.get_setting("display/window/stretch/aspect") == "keep",
		"viewport presentation should preserve the 16:9 aspect ratio"
	)
	_expect(
		bool(ProjectSettings.get_setting("display/window/size/resizable", false)),
		"players should be able to resize the presentation window"
	)


func _test_content_database() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	var errors := database.build_index()
	_expect(errors.is_empty(), "original content database should validate: %s" % [errors])
	_expect(database.actors.size() == 1, "formal slice should register one original actor")
	_expect(database.maps.size() == 1, "formal slice should register one original map")
	_expect(database.items.is_empty(), "formal slice should not keep obsolete lab items")
	_expect(database.skills.is_empty(), "formal slice should not keep obsolete lab skills")
	_expect(database.enemies.is_empty(), "formal slice should not keep obsolete lab enemies")
	_expect(database.shops.is_empty(), "formal slice should not keep obsolete lab shops")
	_expect(
		database.actor(&"actor.roadside.traveler") != null,
		"database should expose the original traveler ID"
	)
	_expect(
		database.map(&"map.roadside.shop") != null,
		"database should expose the roadside shop ID"
	)


func _test_original_assets() -> void:
	var diagnostics := AssetLibrary.validate_assets()
	_expect(diagnostics.is_empty(), "required original assets should exist: %s" % [diagnostics])
	for path: String in AssetLibrary.REQUIRED_ASSETS:
		_expect(not path.begins_with("res://generated/"), "runtime assets must not use generated/")


func _test_directional_frames() -> void:
	var actor := load("res://content/actors/traveler.tres") as ActorDefinition
	_expect(
		actor.field_sprite != null and actor.field_sprite.get_size() == Vector2(72, 128),
		"traveler should use a strict 3x4 sheet of 24x32 frames"
	)
	var frames := DirectionalSpriteFrames.from_3x4_sheet(actor.field_sprite)
	for direction: StringName in DirectionalSpriteFrames.DIRECTIONS:
		_expect(frames.has_animation(direction), "traveler should expose %s" % direction)
		_expect(
			frames.get_frame_count(direction) == 4,
			"%s should play stand-step-stand-step" % direction
		)
		var frame := frames.get_frame_texture(direction, 0) as AtlasTexture
		_expect(
			frame != null and frame.region.size == Vector2(24, 32),
			"%s should crop exact 24x32 cells" % direction
		)


func _test_roadside_scene() -> void:
	var packed := load("res://scenes/maps/roadside_shop.tscn") as PackedScene
	var scene := packed.instantiate() as MapGameScene
	get_root().add_child(scene)
	await process_frame
	_expect(scene != null, "roadside shop should instantiate as MapGameScene")
	_expect(
		scene.ground_layer.tile_set.tile_size == Vector2i(32, 16)
		and scene.ground_layer.tile_set.tile_shape == TileSet.TILE_SHAPE_ISOMETRIC,
		"roadside shop should use strict 32x16 diamond tiles"
	)
	_expect(
		scene.ground_layer.get_used_cells().size() == 252,
		"roadside shop should store its expanded 18x14 layout in TileMapLayer"
	)
	_expect(
		scene.ground_layer.get_used_rect().size == Vector2i(18, 14),
		"roadside shop should expose an exact 18x14 ground rectangle"
	)
	_expect(scene.y_sort_root.y_sort_enabled, "roadside people and props should share YSort")
	var player_camera := scene.player.get_node(^"CameraRig") as Camera2D
	var fixed_camera := scene.get_node(^"FixedCamera") as Camera2D
	_expect(
		player_camera.enabled and not fixed_camera.enabled,
		"the smaller viewport should follow the player instead of showing the whole map"
	)
	var tree := scene.get_node(^"YSortRoot/PineTree") as StaticBody2D
	var shopkeeper := scene.get_node(^"YSortRoot/Shopkeeper") as NpcCharacter
	_expect(
		shopkeeper.sprite_sheet != null
		and shopkeeper.sprite_sheet.get_size() == Vector2(72, 128),
		"shopkeeper should use a matching original 3x4 sheet"
	)
	var interactable := shopkeeper.get_node(^"Interactable") as Interactable
	_expect(
		interactable.event is DialogueEvent,
		"shopkeeper should use an embedded DialogueEvent"
	)
	scene.player.position = Vector2(0, 96)
	var collision := scene.player.move_and_collide(Vector2(0, -32))
	_expect(
		collision != null and collision.get_collider() == tree,
		"tree should physically stop player movement"
	)
	scene.queue_free()
	await process_frame


func _test_game_run_round_trip() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	database.build_index()
	var run := GameRun.new_game(database)
	run.location.map_id = &"map.roadside.shop"
	run.location.spawn_id = &"default"
	run.location.position = Vector2(24, 96)
	run.location.direction = &"east"
	run.location.has_exact_position = true
	var restored := GameRun.from_dictionary(run.to_dictionary())
	_expect(restored != null, "GameRun should round-trip the new content version")
	if restored == null:
		return
	_expect(
		restored.party.leader_id == &"actor.roadside.traveler",
		"GameRun should preserve the original traveler"
	)
	_expect(restored.location.map_id == &"map.roadside.shop", "location should round-trip")
	_expect(restored.location.position == Vector2(24, 96), "exact position should round-trip")


func _test_save_service() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	database.build_index()
	var service := SaveService.new()
	service.configure(database)
	service.configure_slots_directory(TEST_SLOTS)
	var run := GameRun.new_game(database)
	run.location.map_id = &"map.roadside.shop"
	_expect(service.save_run(run, TEST_SAVE) == OK, "SaveService should save original content")
	var restored := service.load_run(TEST_SAVE)
	_expect(
		restored != null and restored.location.map_id == &"map.roadside.shop",
		"SaveService should restore the roadside map"
	)
	_expect(service.save_slot(run, 1) == OK, "formal slot should save")
	var summary := service.slot_summary(1)
	_expect(
		summary.get("map_name") == "斜坡小铺" and summary.get("leader_name") == "旅人",
		"slot summary should use new original display names"
	)
	_remove_if_exists(TEST_SAVE)
	_remove_if_exists(service.slot_path(1))
	_remove_directory_if_empty(TEST_SLOTS)
	service.free()


func _test_settings_service() -> void:
	var root := Node.new()
	get_root().add_child(root)
	var audio := AudioService.new()
	var music_player := AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	audio.add_child(music_player)
	var sound_player := AudioStreamPlayer.new()
	sound_player.name = "SoundPlayer"
	audio.add_child(sound_player)
	root.add_child(audio)
	var service := SettingsService.new()
	root.add_child(service)
	audio.configure()
	service.configure(audio, TEST_SETTINGS)
	service.set_locale(&"en")
	service.set_key_binding(&"interact", KEY_E)
	_expect(service.locale == &"en", "settings should persist locale choice")
	_expect(service.key_for_action(&"interact") == KEY_E, "settings should rebind interact")
	service.set_locale(&"zh_CN", false)
	_remove_if_exists(TEST_SETTINGS)
	root.queue_free()


func _test_scene_stack() -> void:
	var stack := GameSceneStack.new()
	get_root().add_child(stack)
	stack.configure(func() -> GameSceneContext: return GameSceneContext.new())
	var fixture := _pack_scene_stack_fixture()
	_expect(stack.reset(fixture, {"name": "root"}), "scene stack should reset")
	var root_scene := stack.current_scene() as SceneStackTestScene
	_capture_scene_stack_result(stack, fixture)
	await process_frame
	_expect(stack.scene_count() == 2, "scene stack should push a modal scene")
	_expect(root_scene.pause_count == 1, "push should pause the map")
	stack.pop({"closed": true})
	await process_frame
	_expect(_scene_stack_result_received, "pop should resume the awaiting caller")
	_expect(_scene_stack_result == {"closed": true}, "pop should return its result")
	_expect(root_scene.resume_count == 1, "pop should resume the map")
	stack.queue_free()
	await process_frame


func _test_game_root_smoke() -> void:
	var packed := load("res://scenes/root/game_root.tscn") as PackedScene
	var game_root := packed.instantiate() as GameRoot
	get_root().add_child(game_root)
	await process_frame
	_expect(
		game_root.asset_library.diagnostics.is_empty(),
		"GameRoot should initialize only original assets"
	)
	game_root.start_new_game()
	await process_frame
	await process_frame
	var map_scene := game_root.scene_stack.current_scene() as MapGameScene
	_expect(
		map_scene != null and map_scene.map_id == &"map.roadside.shop",
		"new game should enter the formal roadside shop"
	)
	_expect(InputMap.has_action(&"toggle_fullscreen"), "F11 fullscreen action should be registered")
	if map_scene != null:
		var shopkeeper := map_scene.get_node(^"YSortRoot/Shopkeeper") as NpcCharacter
		map_scene.player.position = shopkeeper.position + Vector2(-24, 0)
		map_scene._on_player_interact()
		await process_frame
		_expect(game_root.dialogue_layer.is_active(), "shopkeeper should open formal dialogue")
		while game_root.dialogue_layer.is_active():
			game_root.dialogue_layer.advance_requested.emit()
			await process_frame
		_expect(not game_root.story_director.is_busy(), "dialogue should restore player control")
		map_scene.capture_location()
		game_root.scene_stack.push(game_root.menu_scene)
		await process_frame
		_expect(game_root.scene_stack.scene_count() == 2, "menu should push over the map")
		game_root.scene_stack.pop()
		await process_frame
		_expect(game_root.scene_stack.current_scene() == map_scene, "menu should return to map")
	game_root.queue_free()
	await process_frame


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


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_directory_if_empty(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _ensure_input_actions() -> void:
	for action: StringName in [
		&"move_north", &"move_south", &"move_west", &"move_east", &"interact", &"menu",
	]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
