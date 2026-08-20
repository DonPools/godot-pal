class_name SettingsGameScene
extends GameScene

const ACTION_LABELS := {
	&"move_north": "UI_ACTION_NORTH",
	&"move_south": "UI_ACTION_SOUTH",
	&"move_west": "UI_ACTION_WEST",
	&"move_east": "UI_ACTION_EAST",
	&"aim_north": "UI_ACTION_AIM_NORTH",
	&"aim_south": "UI_ACTION_AIM_SOUTH",
	&"aim_west": "UI_ACTION_AIM_WEST",
	&"aim_east": "UI_ACTION_AIM_EAST",
	&"interact": "UI_ACTION_INTERACT",
	&"menu": "UI_ACTION_MENU",
	&"combat_attack": "UI_ACTION_ATTACK",
	&"combat_skill_one": "UI_ACTION_SKILL_ONE",
	&"combat_skill_two": "UI_ACTION_SKILL_TWO",
	&"combat_skill_three": "UI_ACTION_SKILL_THREE",
	&"combat_dodge": "UI_ACTION_DODGE",
	&"combat_item": "UI_ACTION_ITEM",
	&"combat_stand_ground": "UI_ACTION_STAND_GROUND",
	&"combat_force_move": "UI_ACTION_FORCE_MOVE",
	&"combat_target_next": "UI_ACTION_TARGET_NEXT",
}
const DISPLAY_MODES: Array[StringName] = [
	SettingsService.DISPLAY_MODE_WINDOW_2X,
	SettingsService.DISPLAY_MODE_WINDOW_3X,
	SettingsService.DISPLAY_MODE_FULLSCREEN,
]
const DISPLAY_LABELS := {
	SettingsService.DISPLAY_MODE_WINDOW_2X: "UI_DISPLAY_WINDOW_2X",
	SettingsService.DISPLAY_MODE_WINDOW_3X: "UI_DISPLAY_WINDOW_3X",
	SettingsService.DISPLAY_MODE_FULLSCREEN: "UI_DISPLAY_FULLSCREEN",
}
const BINDING_SLOTS: Array[SettingsService.BindingSlot] = [
	SettingsService.BindingSlot.KEYBOARD,
	SettingsService.BindingSlot.MOUSE,
	SettingsService.BindingSlot.GAMEPAD,
]
const BINDING_SLOT_LABELS := [
	"UI_BINDING_KEYBOARD", "UI_BINDING_MOUSE", "UI_BINDING_GAMEPAD",
]
const DIALOGUE_SPEEDS: Array[float] = [32.0, 48.0, 72.0, 120.0]
const DIALOGUE_SPEED_LABELS := [
	"UI_DIALOGUE_SPEED_SLOW",
	"UI_DIALOGUE_SPEED_STANDARD",
	"UI_DIALOGUE_SPEED_FAST",
	"UI_DIALOGUE_SPEED_VERY_FAST",
]

enum SettingsCategory {
	GAME,
	DISPLAY_AUDIO,
	CONTROLS,
	ACCESSIBILITY,
}

@onready var title_label: Label = $UiLayer/Panel/Title
@onready var music_toggle: CheckButton = $UiLayer/Panel/Music
@onready var sound_toggle: CheckButton = $UiLayer/Panel/Sound
@onready var language_label: Label = $UiLayer/Panel/LanguageLabel
@onready var language_option: OptionButton = $UiLayer/Panel/Language
@onready var display_label: Label = $UiLayer/Panel/DisplayLabel
@onready var display_option: OptionButton = $UiLayer/Panel/Display
@onready var action_list: ItemList = $UiLayer/Panel/Actions
@onready var rebind_button: Button = $UiLayer/Panel/Rebind
@onready var clear_button: Button = $UiLayer/Panel/ClearBinding
@onready var reset_button: Button = $UiLayer/Panel/ResetBindings
@onready var binding_device_label: Label = $UiLayer/Panel/BindingDeviceLabel
@onready var binding_device_option: OptionButton = $UiLayer/Panel/BindingDevice
@onready var movement_deadzone_label: Label = $UiLayer/Panel/MovementDeadzoneLabel
@onready var movement_deadzone_slider: HSlider = $UiLayer/Panel/MovementDeadzone
@onready var aim_deadzone_label: Label = $UiLayer/Panel/AimDeadzoneLabel
@onready var aim_deadzone_slider: HSlider = $UiLayer/Panel/AimDeadzone
@onready var aim_sensitivity_label: Label = $UiLayer/Panel/AimSensitivityLabel
@onready var aim_sensitivity_slider: HSlider = $UiLayer/Panel/AimSensitivity
@onready var dialogue_speed_label: Label = $UiLayer/Panel/DialogueSpeedLabel
@onready var dialogue_speed_option: OptionButton = $UiLayer/Panel/DialogueSpeed
@onready var reduce_flashes_toggle: CheckButton = $UiLayer/Panel/ReduceCombatFlashes
@onready var gamepad_hint: Label = $UiLayer/Panel/GamepadHint
@onready var status_label: Label = $UiLayer/Panel/Status
@onready var page_title: Label = $UiLayer/Panel/PageTitle
@onready var category_description: Label = $UiLayer/Panel/CategoryDescription
@onready var back_hint: Label = $UiLayer/Panel/BackHint
@onready var category_game: Button = $UiLayer/Panel/CategoryGame
@onready var category_display_audio: Button = $UiLayer/Panel/CategoryDisplayAudio
@onready var category_controls: Button = $UiLayer/Panel/CategoryControls
@onready var category_accessibility: Button = $UiLayer/Panel/CategoryAccessibility
@onready var keyboard_tab: Button = $UiLayer/Panel/KeyboardTab
@onready var mouse_tab: Button = $UiLayer/Panel/MouseTab
@onready var gamepad_tab: Button = $UiLayer/Panel/GamepadTab

var _actions: Array[StringName] = []
var _waiting_action: StringName
var _current_category := SettingsCategory.GAME


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
	display_option.item_selected.connect(_select_display)
	rebind_button.pressed.connect(_begin_rebind)
	clear_button.pressed.connect(_clear_binding)
	reset_button.pressed.connect(_reset_bindings)
	binding_device_option.item_selected.connect(_select_binding_device)
	movement_deadzone_slider.drag_ended.connect(_input_tuning_drag_ended)
	aim_deadzone_slider.drag_ended.connect(_input_tuning_drag_ended)
	aim_sensitivity_slider.drag_ended.connect(_input_tuning_drag_ended)
	movement_deadzone_slider.value_changed.connect(_input_tuning_value_changed)
	aim_deadzone_slider.value_changed.connect(_input_tuning_value_changed)
	aim_sensitivity_slider.value_changed.connect(_input_tuning_value_changed)
	dialogue_speed_option.item_selected.connect(_select_dialogue_speed)
	reduce_flashes_toggle.toggled.connect(_toggle_reduce_combat_flashes)
	action_list.item_selected.connect(func(_index: int) -> void: status_label.text = "")
	category_game.pressed.connect(_show_category.bind(SettingsCategory.GAME))
	category_display_audio.pressed.connect(_show_category.bind(SettingsCategory.DISPLAY_AUDIO))
	category_controls.pressed.connect(_show_category.bind(SettingsCategory.CONTROLS))
	category_accessibility.pressed.connect(_show_category.bind(SettingsCategory.ACCESSIBILITY))
	keyboard_tab.pressed.connect(_select_binding_tab.bind(0))
	mouse_tab.pressed.connect(_select_binding_tab.bind(1))
	gamepad_tab.pressed.connect(_select_binding_tab.bind(2))
	_configure_input_controls()
	_configure_accessibility_controls()
	_refresh_text()
	_refresh_actions()
	_show_category(SettingsCategory.GAME)
	category_game.grab_focus()


func _input(event: InputEvent) -> void:
	if _waiting_action.is_empty():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.physical_keycode == KEY_ESCAPE:
			_cancel_rebind()
			get_viewport().set_input_as_handled()
			return
	var binding_event := _binding_event_from_input(event, _selected_binding_slot())
	if binding_event == null:
		return
	var conflict := scene_context.settings_service.conflicting_action(
		_waiting_action,
		_selected_binding_slot(),
		binding_event
	)
	if not conflict.is_empty():
		status_label.text = tr("UI_REBIND_CONFLICT") % [
			tr(ACTION_LABELS[_waiting_action]),
			tr(ACTION_LABELS[conflict]),
		]
		_waiting_action = &""
		get_viewport().set_input_as_handled()
		return
	scene_context.settings_service.set_input_binding(
		_waiting_action,
		_selected_binding_slot(),
		binding_event
	)
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


func _select_display(index: int) -> void:
	if index < 0 or index >= DISPLAY_MODES.size():
		return
	scene_context.settings_service.set_display_mode(DISPLAY_MODES[index])
	status_label.text = tr("UI_DISPLAY_APPLIED")


func _begin_rebind() -> void:
	var selected := action_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _actions.size():
		return
	_waiting_action = _actions[selected[0]]
	status_label.text = tr("UI_REBIND_WAITING") % [
		tr(ACTION_LABELS[_waiting_action]),
		tr(BINDING_SLOT_LABELS[binding_device_option.selected]),
	]


func _clear_binding() -> void:
	var selected := action_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _actions.size():
		return
	if (
		_actions[selected[0]] == &"menu"
		and _selected_binding_slot() == SettingsService.BindingSlot.KEYBOARD
	):
		var escape_event := InputEventKey.new()
		escape_event.physical_keycode = KEY_ESCAPE
		scene_context.settings_service.set_input_binding(
			&"menu",
			SettingsService.BindingSlot.KEYBOARD,
			escape_event
		)
		status_label.text = tr("UI_BINDING_REQUIRED")
		_refresh_actions()
		return
	scene_context.settings_service.clear_input_binding(
		_actions[selected[0]], _selected_binding_slot()
	)
	status_label.text = tr("UI_BINDING_CLEARED")
	_refresh_actions()


func _reset_bindings() -> void:
	scene_context.settings_service.reset_input_bindings()
	movement_deadzone_slider.value = scene_context.settings_service.movement_deadzone
	aim_deadzone_slider.value = scene_context.settings_service.aim_deadzone
	aim_sensitivity_slider.value = scene_context.settings_service.aim_sensitivity
	status_label.text = tr("UI_BINDINGS_RESET")
	_refresh_actions()
	_refresh_tuning_labels()


func _cancel_rebind() -> void:
	_waiting_action = &""
	status_label.text = tr("UI_REBIND_CANCELLED")


func _select_binding_device(_index: int) -> void:
	_cancel_rebind()
	_refresh_actions()
	_refresh_binding_tabs()
	gamepad_hint.visible = (
		_current_category == SettingsCategory.CONTROLS
		and _selected_binding_slot() == SettingsService.BindingSlot.GAMEPAD
	)


func _select_binding_tab(index: int) -> void:
	binding_device_option.select(clampi(index, 0, BINDING_SLOTS.size() - 1))
	_select_binding_device(index)


func _input_tuning_value_changed(_value: float) -> void:
	_refresh_tuning_labels()


func _input_tuning_drag_ended(value_changed: bool) -> void:
	if not value_changed:
		return
	scene_context.settings_service.set_input_tuning(
		float(movement_deadzone_slider.value),
		float(aim_deadzone_slider.value),
		float(aim_sensitivity_slider.value)
	)
	status_label.text = tr("UI_INPUT_TUNING_SAVED")


func _select_dialogue_speed(index: int) -> void:
	if index < 0 or index >= DIALOGUE_SPEEDS.size():
		return
	scene_context.settings_service.set_accessibility(
		DIALOGUE_SPEEDS[index],
		reduce_flashes_toggle.button_pressed
	)
	status_label.text = tr("UI_ACCESSIBILITY_SAVED")


func _toggle_reduce_combat_flashes(enabled: bool) -> void:
	scene_context.settings_service.set_accessibility(
		scene_context.settings_service.dialogue_text_speed,
		enabled
	)
	status_label.text = tr("UI_ACCESSIBILITY_SAVED")


func _refresh_text() -> void:
	title_label.text = tr("UI_SETTINGS_TITLE")
	music_toggle.text = tr("UI_MUSIC")
	sound_toggle.text = tr("UI_SOUND")
	language_label.text = tr("UI_LANGUAGE")
	display_label.text = tr("UI_DISPLAY_MODE")
	rebind_button.text = tr("UI_REBIND")
	clear_button.text = tr("UI_CLEAR_BINDING")
	reset_button.text = tr("UI_RESET_BINDINGS")
	binding_device_label.text = tr("UI_BINDING_DEVICE")
	dialogue_speed_label.text = tr("UI_DIALOGUE_SPEED")
	reduce_flashes_toggle.text = tr("UI_REDUCE_COMBAT_FLASHES")
	gamepad_hint.text = tr("UI_GAMEPAD_HINT")
	category_game.text = tr("UI_SETTINGS_CATEGORY_GAME")
	category_display_audio.text = tr("UI_SETTINGS_CATEGORY_DISPLAY_AUDIO")
	category_controls.text = tr("UI_SETTINGS_CATEGORY_CONTROLS")
	category_accessibility.text = tr("UI_SETTINGS_CATEGORY_ACCESSIBILITY")
	back_hint.text = tr("UI_BACK_HINT")
	_refresh_display_options()
	_refresh_binding_device_options()
	_refresh_dialogue_speed_options()
	_refresh_tuning_labels()


func _refresh_display_options() -> void:
	var selected_mode := scene_context.settings_service.display_mode
	display_option.clear()
	for mode: StringName in DISPLAY_MODES:
		display_option.add_item(tr(DISPLAY_LABELS[mode]))
	var selected_index := DISPLAY_MODES.find(selected_mode)
	display_option.select(maxi(selected_index, 0))


func _refresh_actions() -> void:
	var selected_index := action_list.get_selected_items()[0] if not action_list.get_selected_items().is_empty() else 0
	action_list.clear()
	_actions.clear()
	for action: StringName in SettingsService.REBINDABLE_ACTIONS:
		_actions.append(action)
		action_list.add_item("%s  %s" % [
			tr(ACTION_LABELS[action]),
			scene_context.settings_service.binding_label(action, _selected_binding_slot()),
		])
	if not _actions.is_empty():
		action_list.select(clampi(selected_index, 0, _actions.size() - 1))


func _configure_input_controls() -> void:
	movement_deadzone_slider.min_value = SettingsService.MIN_STICK_DEADZONE
	movement_deadzone_slider.max_value = SettingsService.MAX_STICK_DEADZONE
	movement_deadzone_slider.step = 0.01
	movement_deadzone_slider.value = scene_context.settings_service.movement_deadzone
	aim_deadzone_slider.min_value = SettingsService.MIN_STICK_DEADZONE
	aim_deadzone_slider.max_value = SettingsService.MAX_STICK_DEADZONE
	aim_deadzone_slider.step = 0.01
	aim_deadzone_slider.value = scene_context.settings_service.aim_deadzone
	aim_sensitivity_slider.min_value = SettingsService.MIN_AIM_SENSITIVITY
	aim_sensitivity_slider.max_value = SettingsService.MAX_AIM_SENSITIVITY
	aim_sensitivity_slider.step = 0.05
	aim_sensitivity_slider.value = scene_context.settings_service.aim_sensitivity


func _configure_accessibility_controls() -> void:
	reduce_flashes_toggle.button_pressed = (
		scene_context.settings_service.reduce_combat_flashes
	)
	_refresh_dialogue_speed_options()


func _refresh_binding_device_options() -> void:
	var selected := binding_device_option.selected
	binding_device_option.clear()
	for label: String in BINDING_SLOT_LABELS:
		binding_device_option.add_item(tr(label))
	binding_device_option.select(clampi(selected, 0, BINDING_SLOTS.size() - 1))
	keyboard_tab.text = tr("UI_BINDING_KEYBOARD")
	mouse_tab.text = tr("UI_BINDING_MOUSE")
	gamepad_tab.text = tr("UI_BINDING_GAMEPAD")
	_refresh_binding_tabs()


func _refresh_binding_tabs() -> void:
	var selected := clampi(binding_device_option.selected, 0, BINDING_SLOTS.size() - 1)
	keyboard_tab.button_pressed = selected == 0
	mouse_tab.button_pressed = selected == 1
	gamepad_tab.button_pressed = selected == 2


func _show_category(category: SettingsCategory) -> void:
	_current_category = category
	var show_game := category == SettingsCategory.GAME
	var show_display_audio := category == SettingsCategory.DISPLAY_AUDIO
	var show_controls := category == SettingsCategory.CONTROLS
	var show_accessibility := category == SettingsCategory.ACCESSIBILITY
	language_label.visible = show_game
	language_option.visible = show_game
	music_toggle.visible = show_display_audio
	sound_toggle.visible = show_display_audio
	display_label.visible = show_display_audio
	display_option.visible = show_display_audio
	binding_device_label.visible = false
	binding_device_option.visible = false
	keyboard_tab.visible = show_controls
	mouse_tab.visible = show_controls
	gamepad_tab.visible = show_controls
	action_list.visible = show_controls
	rebind_button.visible = show_controls
	clear_button.visible = show_controls
	reset_button.visible = show_controls
	movement_deadzone_label.visible = show_controls
	movement_deadzone_slider.visible = show_controls
	aim_deadzone_label.visible = show_controls
	aim_deadzone_slider.visible = show_controls
	aim_sensitivity_label.visible = show_controls
	aim_sensitivity_slider.visible = show_controls
	gamepad_hint.visible = (
		show_controls
		and _selected_binding_slot() == SettingsService.BindingSlot.GAMEPAD
	)
	dialogue_speed_label.visible = show_accessibility
	dialogue_speed_option.visible = show_accessibility
	reduce_flashes_toggle.visible = show_accessibility
	category_game.button_pressed = show_game
	category_display_audio.button_pressed = show_display_audio
	category_controls.button_pressed = show_controls
	category_accessibility.button_pressed = show_accessibility
	match category:
		SettingsCategory.GAME:
			page_title.text = tr("UI_SETTINGS_CATEGORY_GAME")
			category_description.text = tr("UI_SETTINGS_DESC_GAME")
		SettingsCategory.DISPLAY_AUDIO:
			page_title.text = tr("UI_SETTINGS_CATEGORY_DISPLAY_AUDIO")
			category_description.text = tr("UI_SETTINGS_DESC_DISPLAY_AUDIO")
		SettingsCategory.CONTROLS:
			page_title.text = tr("UI_SETTINGS_CATEGORY_CONTROLS")
			category_description.text = tr("UI_SETTINGS_DESC_CONTROLS")
		SettingsCategory.ACCESSIBILITY:
			page_title.text = tr("UI_SETTINGS_CATEGORY_ACCESSIBILITY")
			category_description.text = tr("UI_SETTINGS_DESC_ACCESSIBILITY")
	status_label.text = ""


func _refresh_dialogue_speed_options() -> void:
	dialogue_speed_option.clear()
	for label: String in DIALOGUE_SPEED_LABELS:
		dialogue_speed_option.add_item(tr(label))
	var saved_speed := scene_context.settings_service.dialogue_text_speed
	var closest_index := 0
	var closest_distance := INF
	for index: int in range(DIALOGUE_SPEEDS.size()):
		var distance := absf(DIALOGUE_SPEEDS[index] - saved_speed)
		if distance < closest_distance:
			closest_index = index
			closest_distance = distance
	dialogue_speed_option.select(closest_index)


func _refresh_tuning_labels() -> void:
	movement_deadzone_label.text = "%s  %d%%" % [
		tr("UI_MOVEMENT_DEADZONE"),
		roundi(movement_deadzone_slider.value * 100.0),
	]
	aim_deadzone_label.text = "%s  %d%%" % [
		tr("UI_AIM_DEADZONE"),
		roundi(aim_deadzone_slider.value * 100.0),
	]
	aim_sensitivity_label.text = "%s  %.2f×" % [
		tr("UI_AIM_SENSITIVITY"),
		aim_sensitivity_slider.value,
	]


func _selected_binding_slot() -> SettingsService.BindingSlot:
	return BINDING_SLOTS[clampi(binding_device_option.selected, 0, BINDING_SLOTS.size() - 1)]


func _binding_event_from_input(
	event: InputEvent,
	slot: SettingsService.BindingSlot
) -> InputEvent:
	match slot:
		SettingsService.BindingSlot.KEYBOARD:
			if event is InputEventKey and event.pressed and not event.echo:
				return event
		SettingsService.BindingSlot.MOUSE:
			if event is InputEventMouseButton and event.pressed:
				return event
		SettingsService.BindingSlot.GAMEPAD:
			if event is InputEventJoypadButton and event.pressed:
				return event
			if event is InputEventJoypadMotion and absf(event.axis_value) >= 0.65:
				return event
	return null
