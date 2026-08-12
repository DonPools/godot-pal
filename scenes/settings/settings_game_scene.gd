class_name SettingsGameScene
extends GameScene

const ACTION_LABELS := {
	&"move_north": "UI_ACTION_NORTH",
	&"move_south": "UI_ACTION_SOUTH",
	&"move_west": "UI_ACTION_WEST",
	&"move_east": "UI_ACTION_EAST",
	&"interact": "UI_ACTION_INTERACT",
	&"menu": "UI_ACTION_MENU",
}

@onready var title_label: Label = $UiLayer/Panel/Title
@onready var music_toggle: CheckButton = $UiLayer/Panel/Music
@onready var sound_toggle: CheckButton = $UiLayer/Panel/Sound
@onready var language_label: Label = $UiLayer/Panel/LanguageLabel
@onready var language_option: OptionButton = $UiLayer/Panel/Language
@onready var action_list: ItemList = $UiLayer/Panel/Actions
@onready var rebind_button: Button = $UiLayer/Panel/Rebind
@onready var gamepad_hint: Label = $UiLayer/Panel/GamepadHint
@onready var status_label: Label = $UiLayer/Panel/Status

var _actions: Array[StringName] = []
var _waiting_action: StringName


func enter(context: GameSceneContext, arguments: Variant) -> void:
	super.enter(context, arguments)
	music_toggle.button_pressed = context.settings_service.music_enabled()
	sound_toggle.button_pressed = context.settings_service.sound_enabled()
	language_option.add_item("中文")
	language_option.add_item("English")
	language_option.select(1 if context.settings_service.locale == &"en" else 0)
	music_toggle.toggled.connect(context.settings_service.set_music_enabled)
	sound_toggle.toggled.connect(context.settings_service.set_sound_enabled)
	language_option.item_selected.connect(_select_language)
	rebind_button.pressed.connect(_begin_rebind)
	action_list.item_selected.connect(func(_index: int) -> void: status_label.text = "")
	_refresh_text()
	_refresh_actions()
	music_toggle.grab_focus()


func _input(event: InputEvent) -> void:
	if _waiting_action.is_empty() or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode == KEY_ESCAPE:
		_waiting_action = &""
		status_label.text = tr("UI_REBIND_CANCELLED")
	else:
		scene_context.settings_service.set_key_binding(_waiting_action, key_event.physical_keycode)
		_waiting_action = &""
		status_label.text = tr("UI_REBIND_SAVED")
		_refresh_actions()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _waiting_action.is_empty() and event.is_action_pressed(&"ui_cancel"):
		scene_context.scene_stack.pop()
		get_viewport().set_input_as_handled()


func _select_language(index: int) -> void:
	scene_context.settings_service.set_locale(&"en" if index == 1 else &"zh_CN")
	_refresh_text()
	_refresh_actions()


func _begin_rebind() -> void:
	var selected := action_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _actions.size():
		return
	_waiting_action = _actions[selected[0]]
	status_label.text = tr("UI_REBIND_WAITING") % tr(ACTION_LABELS[_waiting_action])


func _refresh_text() -> void:
	title_label.text = tr("UI_SETTINGS_TITLE")
	music_toggle.text = tr("UI_MUSIC")
	sound_toggle.text = tr("UI_SOUND")
	language_label.text = tr("UI_LANGUAGE")
	rebind_button.text = tr("UI_REBIND")
	gamepad_hint.text = tr("UI_GAMEPAD_HINT")


func _refresh_actions() -> void:
	var selected_index := action_list.get_selected_items()[0] if not action_list.get_selected_items().is_empty() else 0
	action_list.clear()
	_actions.clear()
	for action: StringName in SettingsService.REBINDABLE_ACTIONS:
		_actions.append(action)
		action_list.add_item("%s  %s" % [
			tr(ACTION_LABELS[action]),
			scene_context.settings_service.key_label(action),
		])
	if not _actions.is_empty():
		action_list.select(clampi(selected_index, 0, _actions.size() - 1))
