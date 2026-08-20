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
	_configure_input_controls()
	_configure_accessibility_controls()
	_refresh_text()
	_refresh_actions()
	music_toggle.grab_focus()


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
