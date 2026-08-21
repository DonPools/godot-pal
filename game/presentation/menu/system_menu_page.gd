class_name SystemMenuPage
extends MenuPage

signal save_requested
signal load_requested
signal settings_requested
signal return_to_title_requested

@onready var summary: Label = $Summary
@onready var save_button: Button = $Save
@onready var load_button: Button = $Load
@onready var settings_button: Button = $Settings
@onready var return_title_button: Button = $ReturnTitle


func _ready() -> void:
	save_button.pressed.connect(_request_save)
	load_button.pressed.connect(_request_load)
	settings_button.pressed.connect(_request_settings)
	return_title_button.pressed.connect(_request_return_to_title)


func refresh_text() -> void:
	summary.text = tr("UI_MENU_SYSTEM_SUMMARY")
	save_button.text = tr("UI_SAVE")
	load_button.text = tr("UI_LOAD")
	settings_button.text = tr("UI_SETTINGS")
	return_title_button.text = tr("UI_MENU_RETURN_TITLE")


func initial_focus_control() -> Control:
	return save_button


func _request_save() -> void:
	save_requested.emit()


func _request_load() -> void:
	load_requested.emit()


func _request_settings() -> void:
	settings_requested.emit()


func _request_return_to_title() -> void:
	return_to_title_requested.emit()
