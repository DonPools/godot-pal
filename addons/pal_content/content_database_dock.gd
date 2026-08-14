@tool
class_name ContentDatabaseDock
extends VBoxContainer

signal resource_open_requested(resource_value: Resource)

const DATABASE_PATH := "res://content/content_database.tres"

var catalog := ContentCatalog.new()
var selected_resource: Resource
var selected_type: String
var selected_id: StringName

var _type_filter: OptionButton
var _content_list: ItemList
var _summary: RichTextLabel
var _references: RichTextLabel
var _open_button: Button
var _dialogue_panel: VBoxContainer
var _block_filter: OptionButton
var _entry_list: ItemList
var _speaker_edit: LineEdit
var _text_edit: TextEdit
var _save_dialogue_button: Button
var _status: Label


func _ready() -> void:
	name = "Content Database"
	custom_minimum_size = Vector2(330.0, 480.0)
	_build_ui()
	refresh_catalog()


func refresh_catalog() -> void:
	var database := load(DATABASE_PATH) as ContentDatabase
	catalog.build(database)
	_refresh_content_list()
	_status.text = (
		"%d content records" % catalog.items.size()
		if catalog.diagnostics.is_empty()
		else "%d catalog errors" % catalog.diagnostics.size()
	)


func select_content(content_type: String, content_id: StringName) -> bool:
	var resource_value := catalog.resource(content_type, content_id)
	if resource_value == null:
		return false
	selected_type = content_type
	selected_id = content_id
	selected_resource = resource_value
	_show_selected()
	return true


func dialogue_preview_text(dialogue: DialogueDefinition) -> String:
	if dialogue == null:
		return ""
	var lines := PackedStringArray()
	for block: DialogueBlock in dialogue.blocks:
		if block == null:
			continue
		lines.append("[%s]" % block.id)
		for entry: DialogueEntry in block.entries:
			if entry != null:
				lines.append("%s：%s" % [entry.speaker, entry.text])
	return "\n".join(lines)


func save_dialogue_entry(
	dialogue: DialogueDefinition,
	block_index: int,
	entry_index: int,
	speaker: String,
	text: String
) -> Error:
	if (
		dialogue == null
		or block_index < 0
		or block_index >= dialogue.blocks.size()
		or dialogue.blocks[block_index] == null
		or entry_index < 0
		or entry_index >= dialogue.blocks[block_index].entries.size()
		or text.strip_edges().is_empty()
		or dialogue.resource_path.is_empty()
	):
		return ERR_INVALID_PARAMETER
	var entry := dialogue.blocks[block_index].entries[entry_index]
	if entry == null:
		return ERR_INVALID_PARAMETER
	var previous_speaker := entry.speaker
	var previous_text := entry.text
	entry.speaker = speaker
	entry.text = text
	var errors := dialogue.validate()
	if not errors.is_empty():
		entry.speaker = previous_speaker
		entry.text = previous_text
		return ERR_INVALID_DATA
	var save_error := ResourceSaver.save(dialogue, dialogue.resource_path)
	if save_error != OK:
		entry.speaker = previous_speaker
		entry.text = previous_text
	return save_error


func _build_ui() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	_type_filter = OptionButton.new()
	_type_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_type_filter.add_item("All")
	for content_type: String in ContentCatalog.TYPES:
		_type_filter.add_item(content_type.capitalize())
	_type_filter.item_selected.connect(func(_index: int) -> void: _refresh_content_list())
	toolbar.add_child(_type_filter)
	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(refresh_catalog)
	toolbar.add_child(refresh_button)

	_content_list = ItemList.new()
	_content_list.custom_minimum_size.y = 150.0
	_content_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_list.item_selected.connect(_select_list_item)
	add_child(_content_list)

	_open_button = Button.new()
	_open_button.text = "Open in Inspector"
	_open_button.disabled = true
	_open_button.pressed.connect(func() -> void: resource_open_requested.emit(selected_resource))
	add_child(_open_button)

	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.custom_minimum_size.y = 54.0
	add_child(_summary)
	_references = RichTextLabel.new()
	_references.bbcode_enabled = true
	_references.fit_content = true
	_references.custom_minimum_size.y = 54.0
	add_child(_references)

	_build_dialogue_editor()
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


func _build_dialogue_editor() -> void:
	_dialogue_panel = VBoxContainer.new()
	_dialogue_panel.visible = false
	add_child(_dialogue_panel)
	var heading := Label.new()
	heading.text = "Dialogue Editor"
	heading.add_theme_font_size_override("font_size", 16)
	_dialogue_panel.add_child(heading)
	_block_filter = OptionButton.new()
	_block_filter.item_selected.connect(func(_index: int) -> void: _refresh_dialogue_entries())
	_dialogue_panel.add_child(_block_filter)
	_entry_list = ItemList.new()
	_entry_list.custom_minimum_size.y = 80.0
	_entry_list.item_selected.connect(_select_dialogue_entry)
	_dialogue_panel.add_child(_entry_list)
	_speaker_edit = LineEdit.new()
	_speaker_edit.placeholder_text = "Speaker"
	_dialogue_panel.add_child(_speaker_edit)
	_text_edit = TextEdit.new()
	_text_edit.custom_minimum_size.y = 90.0
	_text_edit.placeholder_text = "Dialogue text"
	_dialogue_panel.add_child(_text_edit)
	_save_dialogue_button = Button.new()
	_save_dialogue_button.text = "Save Entry"
	_save_dialogue_button.pressed.connect(_save_current_dialogue_entry)
	_dialogue_panel.add_child(_save_dialogue_button)


func _refresh_content_list() -> void:
	if _content_list == null:
		return
	_content_list.clear()
	var filter: String = (
		"all"
		if _type_filter.selected <= 0
		else String(ContentCatalog.TYPES[_type_filter.selected - 1])
	)
	for record: Dictionary in catalog.list(filter):
		var label := "%s  %s" % [record.get("type"), record.get("id")]
		var display_name := String(record.get("display_name", ""))
		if not display_name.is_empty():
			label += "  —  %s" % display_name
		_content_list.add_item(label)
		_content_list.set_item_metadata(_content_list.item_count - 1, {
			"type": record.get("type"),
			"id": record.get("id"),
		})


func _select_list_item(index: int) -> void:
	var metadata: Variant = _content_list.get_item_metadata(index)
	if metadata is Dictionary:
		select_content(String(metadata.get("type", "")), StringName(metadata.get("id", "")))


func _show_selected() -> void:
	_open_button.disabled = selected_resource == null
	var record := catalog.find(selected_type, selected_id)
	_summary.text = "[b]%s[/b]\n%s" % [selected_id, record.get("path", "")]
	var database := load(DATABASE_PATH) as ContentDatabase
	var refs := catalog.refs_to(selected_id, database)
	var reference_lines := PackedStringArray(["[b]References: %d[/b]" % refs.size()])
	for reference: Dictionary in refs.slice(0, mini(refs.size(), 6)):
		reference_lines.append("%s  %s" % [reference.get("file", ""), reference.get("field", "")])
	_references.text = "\n".join(reference_lines)
	_dialogue_panel.visible = selected_resource is DialogueDefinition
	if _dialogue_panel.visible:
		_refresh_dialogue_blocks()


func _refresh_dialogue_blocks() -> void:
	_block_filter.clear()
	var dialogue := selected_resource as DialogueDefinition
	for block: DialogueBlock in dialogue.blocks:
		_block_filter.add_item(String(block.id) if block != null else "<empty>")
	if _block_filter.item_count > 0:
		_block_filter.select(0)
	_refresh_dialogue_entries()


func _refresh_dialogue_entries() -> void:
	_entry_list.clear()
	_speaker_edit.text = ""
	_text_edit.text = ""
	var dialogue := selected_resource as DialogueDefinition
	if dialogue == null or _block_filter.selected < 0 or _block_filter.selected >= dialogue.blocks.size():
		return
	var block := dialogue.blocks[_block_filter.selected]
	if block == null:
		return
	for entry: DialogueEntry in block.entries:
		_entry_list.add_item(
			"%s：%s" % [entry.speaker, entry.text.left(40)] if entry != null else "<empty>"
		)
	if _entry_list.item_count > 0:
		_entry_list.select(0)
		_select_dialogue_entry(0)


func _select_dialogue_entry(index: int) -> void:
	var dialogue := selected_resource as DialogueDefinition
	if dialogue == null or _block_filter.selected < 0 or _block_filter.selected >= dialogue.blocks.size():
		return
	var block := dialogue.blocks[_block_filter.selected]
	if block == null or index < 0 or index >= block.entries.size() or block.entries[index] == null:
		return
	_speaker_edit.text = block.entries[index].speaker
	_text_edit.text = block.entries[index].text


func _save_current_dialogue_entry() -> void:
	var selected_entries := _entry_list.get_selected_items()
	if selected_entries.is_empty():
		return
	var error := save_dialogue_entry(
		selected_resource as DialogueDefinition,
		_block_filter.selected,
		selected_entries[0],
		_speaker_edit.text,
		_text_edit.text
	)
	_status.text = "Dialogue entry saved" if error == OK else "Dialogue save failed: %s" % error_string(error)
	if error == OK:
		_refresh_dialogue_entries()
