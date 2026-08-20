class_name DialogueLayer
extends Control

signal advance_requested
signal option_selected(option_id: StringName)

const PANEL_DEFAULT_TOP := 204.0
const PANEL_EXPANDED_TOP := 132.0
const TEXT_DEFAULT_BOTTOM := 130.0
const TEXT_OPTIONS_BOTTOM := 114.0

@onready var panel: Panel = $Panel
@onready var portrait_rect: TextureRect = $Panel/Portrait
@onready var speaker_label: Label = $Panel/Speaker
@onready var text_label: Label = $Panel/Text
@onready var wait_icon: Label = $Panel/WaitIcon
@onready var option_container: VBoxContainer = $Panel/Options

var _audio: AudioService
var _settings: SettingsService
var _active: bool = false
var _waiting_for_option: bool = false
var _typing: bool = false
var _typing_tween: Tween


func configure(audio: AudioService, settings: SettingsService = null) -> void:
	_audio = audio
	_settings = settings


func is_active() -> bool:
	return _active


func is_waiting_for_option() -> bool:
	return _waiting_for_option


func is_typing() -> bool:
	return _typing


func complete_typing() -> bool:
	if not _typing:
		return false
	_stop_typing()
	return true


func show_dialogue(definition: DialogueDefinition, block_id: StringName) -> DialogueResult:
	var result := DialogueResult.new()
	if _active:
		push_error("DialogueLayer cannot display overlapping dialogue")
		return result
	if definition == null:
		push_error("show_dialogue requires a DialogueDefinition")
		return result
	var block := definition.block(block_id)
	if block == null:
		push_error("Dialogue %s has no block %s" % [definition.id, block_id])
		return result
	_active = true
	visible = true
	await get_tree().process_frame
	for entry: DialogueEntry in block.entries:
		_show_entry(entry)
		await advance_requested
		_stop_typing()
	if not block.options.is_empty():
		_show_options(block.options)
		result.selected_option_id = await option_selected
		_clear_options()
	_active = false
	visible = false
	return result


func _show_entry(entry: DialogueEntry) -> void:
	_waiting_for_option = false
	panel.offset_top = PANEL_DEFAULT_TOP
	wait_icon.visible = false
	option_container.visible = false
	text_label.offset_bottom = TEXT_DEFAULT_BOTTOM
	speaker_label.text = entry.speaker
	text_label.text = entry.text
	text_label.visible_characters = 0
	portrait_rect.texture = entry.portrait
	portrait_rect.visible = entry.portrait != null
	var text_left := 124.0 if portrait_rect.visible else 28.0
	text_label.offset_left = text_left
	_start_typing()


func _show_options(options: Array[DialogueOption]) -> void:
	_stop_typing()
	_waiting_for_option = true
	panel.offset_top = PANEL_EXPANDED_TOP
	wait_icon.visible = false
	option_container.visible = true
	text_label.offset_bottom = TEXT_OPTIONS_BOTTOM
	for child: Node in option_container.get_children():
		option_container.remove_child(child)
		child.queue_free()
	var first_button: Button
	for option: DialogueOption in options:
		var button := Button.new()
		button.text = option.text
		button.focus_mode = Control.FOCUS_ALL
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override(&"font_size", 18)
		button.pressed.connect(_select_option.bind(option.id))
		option_container.add_child(button)
		if first_button == null:
			first_button = button
	if first_button != null:
		first_button.call_deferred("grab_focus")


func _select_option(option_id: StringName) -> void:
	if _waiting_for_option:
		option_selected.emit(option_id)


func _clear_options() -> void:
	_waiting_for_option = false
	panel.offset_top = PANEL_DEFAULT_TOP
	option_container.visible = false
	for child: Node in option_container.get_children():
		option_container.remove_child(child)
		child.queue_free()


func _start_typing() -> void:
	_stop_typing(false)
	var character_count := text_label.text.length()
	if character_count <= 0:
		text_label.visible_characters = -1
		wait_icon.visible = true
		return
	_typing = true
	var characters_per_second := (
		_settings.dialogue_text_speed
		if _settings != null
		else SettingsService.DEFAULT_DIALOGUE_TEXT_SPEED
	)
	var duration := float(character_count) / maxf(characters_per_second, 1.0)
	_typing_tween = create_tween()
	_typing_tween.tween_method(
		_set_visible_character_progress,
		0.0,
		float(character_count),
		duration
	)
	_typing_tween.finished.connect(_typing_finished)


func _set_visible_character_progress(value: float) -> void:
	text_label.visible_characters = mini(floori(value), text_label.text.length())


func _typing_finished() -> void:
	_typing_tween = null
	_typing = false
	text_label.visible_characters = -1
	wait_icon.visible = _active and not _waiting_for_option


func _stop_typing(show_complete_text: bool = true) -> void:
	if _typing_tween != null and _typing_tween.is_valid():
		_typing_tween.kill()
	_typing_tween = null
	_typing = false
	if show_complete_text:
		text_label.visible_characters = -1
		wait_icon.visible = _active and not _waiting_for_option


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if _waiting_for_option:
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_cancel"):
		if not complete_typing():
			advance_requested.emit()
		get_viewport().set_input_as_handled()
