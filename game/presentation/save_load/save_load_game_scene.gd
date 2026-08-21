class_name SaveLoadGameScene
extends GameScene

@onready var title_label: Label = $UiLayer/Panel/Title
@onready var status_label: Label = $UiLayer/Panel/Status
@onready var hint_label: Label = $UiLayer/Panel/Hint
@onready var slot_buttons: Array[Button] = [
	$UiLayer/Panel/Slot1,
	$UiLayer/Panel/Slot2,
	$UiLayer/Panel/Slot3,
]

var save_mode: bool = false


func enter(context: GameSceneContext, arguments: Variant) -> void:
	super.enter(context, arguments)
	save_mode = bool(arguments.get("save", false)) if arguments is Dictionary else bool(arguments)
	title_label.text = tr("UI_SAVE_TITLE") if save_mode else tr("UI_LOAD_TITLE")
	hint_label.text = tr("UI_SAVE_LOAD_HINT")
	for index: int in range(slot_buttons.size()):
		slot_buttons[index].pressed.connect(_activate_slot.bind(index + 1))
	_refresh_slots()
	slot_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		scene_context.scene_stack.pop()
		get_viewport().set_input_as_handled()


func _activate_slot(slot_index: int) -> void:
	if save_mode:
		var error := scene_context.save_service.save_slot(scene_context.game_run, slot_index)
		status_label.text = (
			tr("UI_SAVE_SUCCEEDED") % slot_index
			if error == OK
			else tr("UI_SAVE_FAILED") % error_string(error)
		)
		_refresh_slots(false)
		return
	var loaded := scene_context.save_service.load_slot(slot_index)
	if loaded == null:
		status_label.text = tr("UI_LOAD_FAILED")
		return
	status_label.text = tr("UI_LOAD_SUCCEEDED") % slot_index
	scene_context.install_loaded_game_run(loaded)


func _refresh_slots(clear_status: bool = true) -> void:
	if clear_status:
		status_label.text = ""
	for index: int in range(slot_buttons.size()):
		var slot_index := index + 1
		var summary := scene_context.save_service.slot_summary(slot_index)
		var button := slot_buttons[index]
		if not summary.get("exists", false):
			button.text = tr("UI_SLOT_EMPTY") % slot_index
			button.disabled = not save_mode
		elif not summary.get("valid", false):
			button.text = tr("UI_SLOT_CORRUPT") % slot_index
			button.disabled = not save_mode
		else:
			button.text = tr("UI_SLOT_SUMMARY") % [
				slot_index,
				String(summary.get("map_name", summary.get("map_id", ""))),
				String(summary.get("leader_name", summary.get("leader_id", ""))),
				int(summary.get("money", 0)),
			]
			button.disabled = false
