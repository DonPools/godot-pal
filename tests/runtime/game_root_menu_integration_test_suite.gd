class_name GameRootMenuIntegrationTestSuite
extends GameRootIntegrationTestSuiteBase


func run(scene_tree: SceneTree) -> PackedStringArray:
	_scene_tree = scene_tree
	await _test_menu_flow()
	return _failures


func _test_menu_flow() -> void:
	var game_root := await _start_game_root()
	_expect(
		game_root.asset_library.diagnostics.is_empty(),
		"GameRoot should initialize only original assets"
	)
	var map_scene := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		map_scene != null
		and map_scene.map_id == &"map.roadside.lantern_pass"
		and game_root.game_run.location.map_id == map_scene.map_id,
		"new game should enter the lantern-pass cultivation MVP"
	)
	_expect(
		map_scene != null
		and map_scene.story_module is LanternPassStory
		and map_scene.get_node(^"WorldRoot/EncounterSources").get_child_count() == 6
		and map_scene.get_node_or_null(^"WorldRoot/LanternKeeper") is NpcCharacter3D,
		"new game should expose the R7 story, six encounters, and lantern keeper"
	)
	_expect(InputMap.has_action(&"toggle_fullscreen"), "F11 fullscreen action should be registered")
	_expect(
		game_root.settings_service.binding_label(
			&"combat_skill_one", SettingsService.BindingSlot.MOUSE
		) == "鼠右"
		and game_root.settings_service.key_for_action(&"combat_skill_two") == KEY_1
		and game_root.settings_service.key_for_action(&"combat_skill_three") == KEY_2
		and game_root.settings_service.key_for_action(&"combat_item") == KEY_Q,
		"GameRoot should install right-click, 1, 2, and Q as the ARPG combat defaults"
	)
	var escape_menu := InputEventKey.new()
	escape_menu.physical_keycode = KEY_ESCAPE
	var start_menu := InputEventJoypadButton.new()
	start_menu.button_index = JOY_BUTTON_START
	_expect(
		InputMap.action_has_event(&"menu", escape_menu)
		and InputMap.action_has_event(&"menu", start_menu),
		"map menu should have Esc and gamepad Start parity"
	)
	var menu_medicine := game_root.content_database.item(&"item.roadside.wound_powder")
	var menu_equipment := game_root.content_database.item(
		&"item.roadside.returning_sword_case"
	)
	game_root.game_run.inventory.add_item(menu_medicine, 2)
	game_root.game_run.inventory.add_item(menu_equipment, 1)
	var open_menu := InputEventAction.new()
	open_menu.action = &"menu"
	open_menu.pressed = true
	game_root._unhandled_input(open_menu)
	await _scene_tree.process_frame
	_expect(
		game_root.scene_stack.current_scene() is MenuGameScene,
		"the menu action should pause the active map and open the menu scene"
	)
	var menu_scene := game_root.scene_stack.current_scene() as MenuGameScene
	_expect(
		menu_scene != null
		and menu_scene.inventory_page.empty.visible
		== (menu_scene.inventory_page.items.item_count == 0)
		and not menu_scene.status_page.summary.text.is_empty()
		and menu_scene.get_node(^"UiLayer/Panel/Tabs/Status").has_focus(),
		"pause menu should expose status, inventory empty state, and a visible focus target"
	)
	menu_scene.show_page(MenuGameScene.Page.INVENTORY, true)
	_expect(
		menu_scene.inventory_page.items.item_count == 2
		and menu_scene.inventory_page.items.has_focus(),
		"inventory page should list carried items and own focus"
	)
	menu_scene.inventory_page.items.select(0)
	menu_scene.inventory_page.select_item(0)
	menu_scene.inventory_page.assign_selected_quick_item()
	_expect(
		game_root.game_run.party.leader().battle_item_id == menu_medicine.id,
		"inventory page should configure the selected battle item through its transaction"
	)
	menu_scene.show_page(MenuGameScene.Page.EQUIPMENT, true)
	_expect(
		menu_scene.equipment_page.candidates.item_count == 1,
		"equipment page should list compatible carried artifacts"
	)
	menu_scene.equipment_page.candidates.select(0)
	menu_scene.equipment_page.select_candidate(0)
	menu_scene.equipment_page.equip_selected_candidate()
	_expect(
		game_root.game_run.party.leader().equipment.get(&"weapon") == menu_equipment.id,
		"equipment page should equip the selected artifact atomically"
	)
	menu_scene.show_page(MenuGameScene.Page.SKILLS, true)
	menu_scene.skills_page.learned_skills.select(0)
	menu_scene.skills_page.select_learned_skill(0)
	menu_scene.skills_page.assign_selected_skill(2)
	_expect(
		game_root.game_run.party.leader().battle_skill_ids[2]
		== &"skill.roadside.wind_edge",
		"skills page should move a learned skill into the selected battle slot"
	)
	menu_scene.skills_page.assign_selected_skill(0)
	menu_scene.show_page(MenuGameScene.Page.SYSTEM, true)
	menu_scene.system_page.settings_button.grab_focus()
	menu_scene.system_page.settings_button.pressed.emit()
	await _scene_tree.process_frame
	_expect(
		game_root.scene_stack.current_scene() is SettingsGameScene,
		"system page should push the settings scene"
	)
	game_root.scene_stack.pop()
	await _scene_tree.process_frame
	menu_scene = game_root.scene_stack.current_scene() as MenuGameScene
	_expect(
		menu_scene != null
		and menu_scene.current_page() == MenuGameScene.Page.SYSTEM
		and menu_scene.system_page.settings_button.has_focus(),
		"returning from a child scene should preserve the menu page and focus"
	)
	var close_menu := InputEventAction.new()
	close_menu.action = &"ui_cancel"
	close_menu.pressed = true
	menu_scene.get_viewport().push_input(close_menu)
	await _scene_tree.process_frame
	map_scene = game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		map_scene != null,
		"Esc/B should return from the menu to the same map"
	)
	game_root._unhandled_input(open_menu)
	await _scene_tree.process_frame
	var final_menu := game_root.scene_stack.current_scene() as MenuGameScene
	if final_menu != null:
		final_menu.show_page(MenuGameScene.Page.SYSTEM, false)
		final_menu.system_page.return_title_button.pressed.emit()
	await _scene_tree.process_frame
	_expect(
		game_root.scene_stack.current_scene() is TitleGameScene
		and game_root.scene_stack.scene_count() == 1,
		"system menu should reset the scene stack back to the title"
	)
	await _dispose_game_root(game_root)
