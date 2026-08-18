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
var _active: bool = false
var _waiting_for_option: bool = false


func configure(audio: AudioService) -> void:
	_audio = audio


func is_active() -> bool:
	return _active


func is_waiting_for_option() -> bool:
	return _waiting_for_option


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
	wait_icon.visible = true
	option_container.visible = false
	text_label.offset_bottom = TEXT_DEFAULT_BOTTOM
	speaker_label.text = entry.speaker
	text_label.text = entry.text
	portrait_rect.texture = entry.portrait
	portrait_rect.visible = entry.portrait != null
	var text_left := 124.0 if portrait_rect.visible else 28.0
	text_label.offset_left = text_left


func _show_options(options: Array[DialogueOption]) -> void:
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


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if _waiting_for_option:
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_cancel"):
		advance_requested.emit()
		get_viewport().set_input_as_handled()
