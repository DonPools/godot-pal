class_name SettingsTestSuite
extends RefCounted

const TEST_SETTINGS := "res://tests/.tmp_roadside_settings.cfg"

var _failures: PackedStringArray = []


func run(scene_tree: SceneTree) -> PackedStringArray:
	_test_input_binding_codec()
	_test_settings_service(scene_tree)
	return _failures


func _test_input_binding_codec() -> void:
	var source_key := InputEventKey.new()
	source_key.keycode = KEY_K
	var normalized_key := InputBindingCodec.normalized_event(
		source_key,
		InputBindingCodec.Device.KEYBOARD
	) as InputEventKey
	var source_axis := InputEventJoypadMotion.new()
	source_axis.axis = JOY_AXIS_RIGHT_X
	source_axis.axis_value = -0.25
	var normalized_axis := InputBindingCodec.normalized_event(
		source_axis,
		InputBindingCodec.Device.GAMEPAD
	) as InputEventJoypadMotion
	var decoded_axis := InputBindingCodec.decode(
		InputBindingCodec.encode(normalized_axis),
		InputBindingCodec.Device.GAMEPAD
	) as InputEventJoypadMotion
	_expect(
		normalized_key != null
		and normalized_key.physical_keycode == KEY_K
		and normalized_axis != null
		and normalized_axis.axis == JOY_AXIS_RIGHT_X
		and normalized_axis.axis_value == -1.0
		and decoded_axis != null
		and decoded_axis.axis == normalized_axis.axis
		and decoded_axis.axis_value == normalized_axis.axis_value,
		"input binding codec should normalize and round-trip keyboard and axis bindings"
	)
	_expect(
		InputBindingCodec.decode(
			"mouse:%d" % int(MOUSE_BUTTON_LEFT),
			InputBindingCodec.Device.KEYBOARD
		) == null
		and not InputBindingCodec.event_matches_device(
			source_key,
			InputBindingCodec.Device.MOUSE
		),
		"input binding codec should reject bindings from a different device"
	)


func _test_settings_service(scene_tree: SceneTree) -> void:
	var root := Node.new()
	scene_tree.root.add_child(root)
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
	service.set_key_binding(&"combat_skill_three", KEY_G)
	var mouse_binding := InputEventMouseButton.new()
	mouse_binding.button_index = MOUSE_BUTTON_MIDDLE
	service.set_input_binding(
		&"combat_skill_one", SettingsService.BindingSlot.MOUSE, mouse_binding
	)
	var gamepad_binding := InputEventJoypadButton.new()
	gamepad_binding.button_index = JOY_BUTTON_LEFT_STICK
	service.set_input_binding(
		&"combat_target_next", SettingsService.BindingSlot.GAMEPAD, gamepad_binding
	)
	service.set_input_tuning(0.22, 0.31, 1.35)
	service.set_accessibility(72.0, true)
	service.set_display_mode(SettingsService.DISPLAY_MODE_WINDOW_3X)
	service.set_display_mode(SettingsService.DISPLAY_MODE_FULLSCREEN)
	_expect(service.locale == &"en", "settings should persist locale choice")
	_expect(service.key_for_action(&"interact") == KEY_E, "settings should rebind interact")
	_expect(
		service.key_for_action(&"combat_skill_three") == KEY_G,
		"settings should rebind combat actions shown by the HUD"
	)
	_expect(
		service.binding_label(&"combat_skill_one", SettingsService.BindingSlot.MOUSE) == "MMB"
		and service.binding_label(
			&"combat_target_next", SettingsService.BindingSlot.GAMEPAD
		) == "L3",
		"settings should localize independent mouse and gamepad bindings"
	)
	var framework_hud := (
		load("res://framework/presentation/action_combat_3d/map_hud_3d.tscn")
		as PackedScene
	).instantiate() as MapHud3D
	root.add_child(framework_hud)
	framework_hud.configure(service)
	framework_hud.show_rejection(
		BattleActionRequestResult.Rejection.INSUFFICIENT_RESOURCE
	)
	_expect(
		(framework_hud.get_node(^"BattlePanel/ActionBar/Margin/Slots/Basic/Rows/Name") as Label).text
		== "Attack"
		and framework_hud.feedback_label.text == "Not enough Qi",
		"framework combat HUD should honor the active English locale"
	)
	framework_hud.queue_free()
	var config := ConfigFile.new()
	_expect(config.load(TEST_SETTINGS) == OK, "settings should save display preferences")
	_expect(
		config.get_value("display", "window_mode") == "fullscreen"
		and config.get_value("display", "windowed_mode") == "window_3x",
		"settings should preserve fullscreen and the last exact window scale"
	)
	_expect(
		int(config.get_value("input", "version", 0))
		== SettingsService.INPUT_BINDINGS_VERSION,
		"settings should persist the current input binding version"
	)
	_expect(
		is_equal_approx(float(config.get_value("input", "movement_deadzone")), 0.22)
		and is_equal_approx(float(config.get_value("input", "aim_deadzone")), 0.31)
		and is_equal_approx(float(config.get_value("input", "aim_sensitivity")), 1.35)
		and config.get_value("input_mouse", "combat_skill_one") == "mouse:3"
		and config.get_value("input_gamepad", "combat_target_next")
		== "button:%d" % int(JOY_BUTTON_LEFT_STICK),
		"settings should persist stick tuning and device-specific bindings"
	)
	_expect(
		is_equal_approx(
			float(config.get_value("accessibility", "dialogue_text_speed")), 72.0
		)
		and bool(config.get_value("accessibility", "reduce_combat_flashes")),
		"settings should persist dialogue pacing and reduced combat flashes"
	)
	service.load_settings()
	_expect(
		is_equal_approx(service.movement_deadzone, 0.22)
		and is_equal_approx(service.aim_deadzone, 0.31)
		and is_equal_approx(service.aim_sensitivity, 1.35)
		and is_equal_approx(service.dialogue_text_speed, 72.0)
		and service.reduce_combat_flashes,
		"settings should restore clamped input tuning and accessibility preferences"
	)
	service.toggle_fullscreen(false)
	_expect(
		service.display_mode == SettingsService.DISPLAY_MODE_WINDOW_3X,
		"leaving fullscreen should restore the last windowed scale"
	)
	service.set_display_mode(&"unsupported", false)
	_expect(
		service.display_mode == SettingsService.DISPLAY_MODE_WINDOW_2X,
		"unknown display modes should fall back to the default 2x window"
	)
	service.set_display_mode(SettingsService.DISPLAY_MODE_WINDOW_3X, false)
	var settings_scene := (
		load("res://game/presentation/settings/settings_game_scene.tscn") as PackedScene
	).instantiate() as SettingsGameScene
	root.add_child(settings_scene)
	var context := GameSceneContext.new()
	context.settings_service = service
	settings_scene.enter(context, null)
	var display_option := settings_scene.get_node(^"UiLayer/Panel/Display") as OptionButton
	var binding_device_option := settings_scene.get_node(
		^"UiLayer/Panel/BindingDevice"
	) as OptionButton
	var action_list := settings_scene.get_node(^"UiLayer/Panel/Actions") as ItemList
	var dialogue_speed := settings_scene.get_node(
		^"UiLayer/Panel/DialogueSpeed"
	) as OptionButton
	var reduce_flashes := settings_scene.get_node(
		^"UiLayer/Panel/ReduceCombatFlashes"
	) as CheckButton
	_expect(
		display_option.item_count == SettingsService.SUPPORTED_DISPLAY_MODES.size()
		and display_option.selected == 1,
		"settings UI should expose 2x, 3x, and fullscreen and select the saved mode"
	)
	_expect(
		binding_device_option.item_count == 3
		and action_list.item_count == SettingsService.REBINDABLE_ACTIONS.size(),
		"settings UI should expose keyboard, mouse, and gamepad bindings for every action"
	)
	_expect(
		dialogue_speed.item_count == SettingsGameScene.DIALOGUE_SPEEDS.size()
		and dialogue_speed.selected == 2
		and reduce_flashes.button_pressed,
		"settings UI should expose saved dialogue speed and reduced-flash controls"
	)
	var category_game := settings_scene.get_node(
		^"UiLayer/Panel/CategoryGame"
	) as Button
	var keyboard_tab := settings_scene.get_node(^"UiLayer/Panel/KeyboardTab") as Button
	_expect(
		category_game.button_pressed
		and (settings_scene.get_node(^"UiLayer/Panel/Language") as Control).visible
		and not action_list.visible,
		"settings should open on one focused category instead of a flat tool panel"
	)
	settings_scene._show_category(SettingsGameScene.SettingsCategory.CONTROLS)
	_expect(
		keyboard_tab.visible
		and keyboard_tab.button_pressed
		and action_list.visible
		and not (settings_scene.get_node(^"UiLayer/Panel/Language") as Control).visible,
		"controls should expose device tabs and the action list on their own page"
	)
	var conflicting_key := InputEventKey.new()
	conflicting_key.physical_keycode = KEY_E
	_expect(
		service.conflicting_action(
			&"combat_item",
			SettingsService.BindingSlot.KEYBOARD,
			conflicting_key
		) == &"interact",
		"rebinding should identify an existing same-device binding conflict"
	)
	var secondary_menu_key := InputEventKey.new()
	secondary_menu_key.physical_keycode = KEY_M
	_expect(
		service.conflicting_action(
			&"combat_item",
			SettingsService.BindingSlot.KEYBOARD,
			secondary_menu_key
		) == &"menu",
		"conflict checks should include the required secondary menu shortcut"
	)
	var feedback := CombatFeedback3D.new()
	root.add_child(feedback)
	feedback.configure(service)
	var flash_actor := Node3D.new()
	var flash_mesh := MeshInstance3D.new()
	flash_mesh.mesh = BoxMesh.new()
	flash_actor.add_child(flash_mesh)
	root.add_child(flash_actor)
	feedback.flash_actor(flash_actor)
	_expect(
		flash_mesh.material_overlay == null
		and feedback.active_flash_count() == 0,
		"reduced-flash mode should skip actor overlay flashes"
	)
	feedback.queue_free()
	flash_actor.queue_free()
	for event: InputEvent in InputMap.action_get_events(&"combat_skill_one"):
		if event is InputEventKey:
			InputMap.action_erase_event(&"combat_skill_one", event)
	service.set_key_binding(&"combat_skill_two", KEY_1, false)
	service.set_key_binding(&"combat_skill_three", KEY_2, false)
	service.set_key_binding(&"combat_item", KEY_Q, false)
	var legacy_config := ConfigFile.new()
	legacy_config.set_value("input", "combat_skill_one", int(KEY_Q))
	legacy_config.set_value("input", "combat_skill_two", int(KEY_E))
	legacy_config.set_value("input", "combat_skill_three", int(KEY_F))
	legacy_config.set_value("input", "combat_item", int(KEY_R))
	_expect(
		legacy_config.save(TEST_SETTINGS) == OK,
		"settings test should write a legacy input fixture"
	)
	service.load_settings()
	_expect(
		service.key_for_action(&"combat_skill_one") == KEY_NONE
		and service.key_for_action(&"combat_skill_two") == KEY_1
		and service.key_for_action(&"combat_skill_three") == KEY_2
		and service.key_for_action(&"combat_item") == KEY_Q,
		"legacy Q/E/F/R bindings should migrate to the ARPG defaults"
	)
	service.reset_input_bindings(false)
	var escape_key := InputEventKey.new()
	escape_key.physical_keycode = KEY_ESCAPE
	var menu_key := InputEventKey.new()
	menu_key.physical_keycode = KEY_M
	var north_arrow := InputEventKey.new()
	north_arrow.physical_keycode = KEY_UP
	var south_arrow := InputEventKey.new()
	south_arrow.physical_keycode = KEY_DOWN
	var west_arrow := InputEventKey.new()
	west_arrow.physical_keycode = KEY_LEFT
	var east_arrow := InputEventKey.new()
	east_arrow.physical_keycode = KEY_RIGHT
	_expect(
		InputMap.action_has_event(&"menu", escape_key)
		and InputMap.action_has_event(&"menu", menu_key)
		and InputMap.action_has_event(&"move_north", north_arrow)
		and InputMap.action_has_event(&"move_south", south_arrow)
		and InputMap.action_has_event(&"move_west", west_arrow)
		and InputMap.action_has_event(&"move_east", east_arrow),
		"reset defaults should preserve menu and arrow-key secondary shortcuts"
	)
	service.set_locale(&"zh_CN", false)
	_remove_if_exists(TEST_SETTINGS)
	root.queue_free()


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
