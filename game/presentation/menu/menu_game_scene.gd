class_name MenuGameScene
extends GameScene

enum Page {
	STATUS,
	INVENTORY,
	EQUIPMENT,
	SKILLS,
	SYSTEM,
}

@onready var title_label: Label = $UiLayer/Panel/Title
@onready var hint_label: Label = $UiLayer/Panel/Hint
@onready var status_page: StatusMenuPage = $UiLayer/Panel/Pages/StatusPage
@onready var inventory_page: InventoryMenuPage = $UiLayer/Panel/Pages/InventoryPage
@onready var equipment_page: EquipmentMenuPage = $UiLayer/Panel/Pages/EquipmentPage
@onready var skills_page: SkillsMenuPage = $UiLayer/Panel/Pages/SkillsPage
@onready var system_page: SystemMenuPage = $UiLayer/Panel/Pages/SystemPage
@onready var _tab_buttons: Array[Button] = [
	$UiLayer/Panel/Tabs/Status,
	$UiLayer/Panel/Tabs/Inventory,
	$UiLayer/Panel/Tabs/Equipment,
	$UiLayer/Panel/Tabs/Skills,
	$UiLayer/Panel/Tabs/System,
]
@onready var _pages: Array[MenuPage] = [
	status_page,
	inventory_page,
	equipment_page,
	skills_page,
	system_page,
]

var _current_page: Page = Page.STATUS
var _resume_focus: Control


func enter(context: GameSceneContext, _arguments: Variant) -> void:
	super.enter(context, _arguments)
	for index: int in range(_tab_buttons.size()):
		_tab_buttons[index].pressed.connect(show_page.bind(index, true))
	for page: MenuPage in _pages:
		page.configure(context.content_database, context.game_run)
		page.hint_requested.connect(_show_hint)
		page.content_changed.connect(_refresh_all_pages)
	system_page.save_requested.connect(_open_save)
	system_page.load_requested.connect(_open_load)
	system_page.settings_requested.connect(_open_settings)
	system_page.return_to_title_requested.connect(_return_to_title)
	_refresh_text()
	_refresh_all_pages()
	show_page(Page.STATUS, true)
	hint_label.text = tr("UI_MENU_HINT_BACK")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel") and not event.is_action_pressed(&"menu"):
		return
	if inventory_page.has_open_modal():
		inventory_page.close_modal()
	else:
		scene_context.scene_stack.pop()
	get_viewport().set_input_as_handled()


func resume_scene(result: Variant = null) -> void:
	super.resume_scene(result)
	for page: MenuPage in _pages:
		page.configure(scene_context.content_database, scene_context.game_run)
	_refresh_text()
	_refresh_all_pages()
	show_page(_current_page, false)
	if is_instance_valid(_resume_focus) and _resume_focus.is_visible_in_tree():
		_resume_focus.grab_focus()
	else:
		_focus_current_page()
	_resume_focus = null
	hint_label.text = tr("UI_MENU_HINT_BACK")


func show_page(page_index: int, focus_page: bool = true) -> void:
	if page_index < 0 or page_index >= _pages.size():
		push_error("MenuGameScene received invalid page index %d" % page_index)
		return
	_current_page = page_index as Page
	for index: int in range(_pages.size()):
		_pages[index].visible = index == page_index
		_tab_buttons[index].button_pressed = index == page_index
	_pages[page_index].refresh()
	if focus_page:
		_focus_current_page()


func current_page() -> Page:
	return _current_page


func _refresh_text() -> void:
	title_label.text = tr("UI_MENU_TITLE")
	var tab_keys := [
		"UI_MENU_STATUS", "UI_MENU_INVENTORY", "UI_MENU_EQUIPMENT",
		"UI_MENU_SKILLS", "UI_MENU_SYSTEM",
	]
	for index: int in range(_tab_buttons.size()):
		_tab_buttons[index].text = tr(tab_keys[index])
	for page: MenuPage in _pages:
		page.refresh_text()


func _refresh_all_pages() -> void:
	for page: MenuPage in _pages:
		page.refresh()


func _focus_current_page() -> void:
	var focus_control := _pages[int(_current_page)].initial_focus_control()
	if focus_control != null and focus_control.is_visible_in_tree():
		focus_control.grab_focus()
	else:
		_tab_buttons[int(_current_page)].grab_focus()


func _open_save() -> void:
	if scene_context.save_load_scene != null:
		_resume_focus = system_page.save_button
		scene_context.scene_stack.push(scene_context.save_load_scene, {"save": true})


func _open_load() -> void:
	if scene_context.save_load_scene != null:
		_resume_focus = system_page.load_button
		scene_context.scene_stack.push(scene_context.save_load_scene, {"save": false})


func _open_settings() -> void:
	if scene_context.settings_scene != null:
		_resume_focus = system_page.settings_button
		scene_context.scene_stack.push(scene_context.settings_scene)


func _return_to_title() -> void:
	scene_context.request_return_to_title()


func _show_hint(message: String) -> void:
	hint_label.text = message
