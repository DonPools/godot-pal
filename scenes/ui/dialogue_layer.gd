class_name DialogueLayer
extends Control

signal advance_requested

@onready var panel: Panel = $Panel
@onready var portrait_rect: TextureRect = $Panel/Portrait
@onready var speaker_label: Label = $Panel/Speaker
@onready var text_label: Label = $Panel/Text
@onready var wait_icon: TextureRect = $Panel/WaitIcon

var _audio: AudioService
var _active: bool = false


func configure(audio: AudioService) -> void:
	_audio = audio


func is_active() -> bool:
	return _active


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
	_active = false
	visible = false
	return result


func _show_entry(entry: DialogueEntry) -> void:
	speaker_label.text = entry.speaker
	text_label.text = entry.text
	portrait_rect.texture = entry.portrait
	portrait_rect.visible = entry.portrait != null
	var text_left := 74.0 if portrait_rect.visible else 12.0
	speaker_label.offset_left = text_left
	text_label.offset_left = text_left


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_cancel"):
		advance_requested.emit()
		get_viewport().set_input_as_handled()
