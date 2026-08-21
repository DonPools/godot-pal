class_name InventoryMenuPage
extends MenuPage

const ALL_CATEGORIES := -1

@onready var categories: ItemList = $Categories
@onready var capacity: Label = $Capacity
@onready var items: ItemList = $Items
@onready var empty: Label = $Empty
@onready var item_icon: TextureRect = $Icon
@onready var item_name: Label = $Name
@onready var item_quantity: Label = $Quantity
@onready var item_description: Label = $Description
@onready var item_rules: Label = $Rules
@onready var use_button: Button = $Use
@onready var quick_button: Button = $Quick
@onready var discard_button: Button = $Discard
@onready var discard_dialog: ConfirmationDialog = $DiscardDialog
@onready var discard_prompt: Label = $DiscardDialog/Prompt
@onready var discard_quantity: SpinBox = $DiscardDialog/Quantity

var _category: int = ALL_CATEGORIES
var _item_ids: Array[StringName] = []
var _pending_discard_item_id: StringName


func _ready() -> void:
	categories.item_selected.connect(select_category)
	items.item_selected.connect(select_item)
	items.item_activated.connect(activate_item)
	use_button.pressed.connect(use_selected_item)
	quick_button.pressed.connect(assign_selected_quick_item)
	discard_button.pressed.connect(request_discard_selected_item)
	discard_dialog.confirmed.connect(confirm_discard)


func refresh_text() -> void:
	empty.text = tr("UI_MENU_CATEGORY_EMPTY")
	use_button.text = tr("UI_MENU_USE")
	quick_button.text = tr("UI_MENU_SET_QUICK")
	discard_button.text = tr("UI_MENU_DISCARD")
	discard_dialog.title = tr("UI_MENU_DISCARD_TITLE")
	discard_dialog.ok_button_text = tr("UI_MENU_DISCARD_CONFIRM")
	discard_dialog.cancel_button_text = tr("UI_MENU_CANCEL")
	_refresh_category_labels()


func refresh() -> void:
	var previous_id := selected_item_id()
	items.clear()
	_item_ids.clear()
	if _game_run == null or _database == null:
		_clear_detail()
		return
	for item_id: StringName in _game_run.inventory.item_ids():
		var item := _database.item(item_id)
		if item == null or (_category >= 0 and int(item.category) != _category):
			continue
		_item_ids.append(item_id)
		items.add_item(
			"%s  ×%d" % [item.display_name, _game_run.inventory.quantity(item_id)],
			item.icon
		)
	capacity.text = tr("UI_MENU_CAPACITY") % [
		_game_run.inventory.occupied_capacity(),
		_game_run.inventory.max_distinct_items,
	]
	empty.visible = items.item_count == 0
	if items.item_count == 0:
		_clear_detail()
		return
	var selected := _item_ids.find(previous_id)
	selected = selected if selected >= 0 else 0
	items.select(selected)
	select_item(selected)


func initial_focus_control() -> Control:
	return items if items.item_count > 0 else categories


func has_open_modal() -> bool:
	return discard_dialog.visible


func close_modal() -> void:
	discard_dialog.hide()


func select_category(index: int) -> void:
	_category = index - 1
	refresh()
	if items.item_count > 0:
		items.grab_focus()


func selected_item_id() -> StringName:
	var selected := items.get_selected_items()
	return (
		_item_ids[selected[0]]
		if not selected.is_empty() and selected[0] < _item_ids.size()
		else &""
	)


func select_item(index: int) -> void:
	if index < 0 or index >= _item_ids.size():
		_clear_detail()
		return
	var item := _database.item(_item_ids[index])
	if item == null:
		_clear_detail()
		return
	item_icon.texture = item.icon
	item_name.text = item.display_name
	item_quantity.text = tr("UI_MENU_QUANTITY") % _game_run.inventory.quantity(item.id)
	item_description.text = item.description
	var scope := (
		tr("UI_MENU_FIELD_AND_BATTLE")
		if item.usable_in_field and item.usable_in_battle
		else tr("UI_MENU_FIELD_ONLY")
		if item.usable_in_field
		else tr("UI_MENU_BATTLE_ONLY")
		if item.usable_in_battle
		else tr("UI_MENU_NOT_USABLE")
	)
	item_rules.text = "%s · %s" % [
		scope,
		tr("UI_MENU_KEY_CAPACITY_FREE")
		if item.category == ItemDefinition.Category.KEY_ITEM
		else tr("UI_MENU_USES_CAPACITY"),
	]
	use_button.text = tr("UI_MENU_EQUIP") if item is EquipmentDefinition else tr("UI_MENU_USE")
	use_button.disabled = not item is EquipmentDefinition and not item.can_be_used_in_field()
	quick_button.disabled = (
		not item.can_be_used_in_battle()
		or _game_run.inventory.quantity(item.id) <= 0
	)
	discard_button.disabled = not item.can_discard


func activate_item(index: int) -> void:
	if index >= 0 and index < _item_ids.size():
		items.select(index)
		use_selected_item()


func use_selected_item() -> void:
	var item := _selected_item()
	var leader := _leader()
	var definition := _leader_definition()
	if item == null or leader == null or definition == null:
		return
	if item is EquipmentDefinition:
		var equipment_result := EquipmentTransaction.equip(
			_game_run, leader, item as EquipmentDefinition, _database
		)
		_request_equipment_result_hint(equipment_result, item)
	else:
		var result := ItemUseTransaction.use_on_actor(
			_game_run, item, leader, definition, _database
		)
		match result.outcome:
			ItemUseResult.Outcome.USED:
				hint_requested.emit(
					tr("UI_MENU_USED") % [item.display_name, result.changed_amount]
				)
			ItemUseResult.Outcome.NO_EFFECT:
				hint_requested.emit(tr("UI_MENU_NO_EFFECT") % item.display_name)
			_:
				hint_requested.emit(tr("UI_MENU_CANNOT_USE") % item.display_name)
	content_changed.emit()


func assign_selected_quick_item() -> void:
	var item := _selected_item()
	if item == null:
		hint_requested.emit(tr("UI_MENU_QUICK_FAILED"))
		return
	var result := BattleItemLoadoutTransaction.assign(
		_game_run, _leader(), item, _database
	)
	match result.outcome:
		BattleItemLoadoutResult.Outcome.ASSIGNED:
			hint_requested.emit(tr("UI_MENU_QUICK_ASSIGNED") % item.display_name)
		BattleItemLoadoutResult.Outcome.UNCHANGED:
			hint_requested.emit(tr("UI_MENU_QUICK_UNCHANGED") % item.display_name)
		_:
			hint_requested.emit(tr("UI_MENU_QUICK_FAILED"))
	content_changed.emit()


func request_discard_selected_item() -> void:
	var item := _selected_item()
	if item == null or not item.can_discard:
		return
	_pending_discard_item_id = item.id
	discard_prompt.text = tr("UI_MENU_DISCARD_PROMPT") % item.display_name
	discard_quantity.max_value = _game_run.inventory.quantity(item.id)
	discard_quantity.value = 1
	discard_dialog.popup_centered()


func confirm_discard() -> void:
	var item := _database.item(_pending_discard_item_id)
	var quantity := int(discard_quantity.value)
	var result := ItemDiscardTransaction.discard(_game_run, item, quantity)
	if result.succeeded():
		hint_requested.emit(tr("UI_MENU_DISCARDED") % [item.display_name, quantity])
	else:
		hint_requested.emit(tr("UI_MENU_DISCARD_FAILED"))
	_pending_discard_item_id = &""
	content_changed.emit()


func _selected_item() -> ItemDefinition:
	var item_id := selected_item_id()
	return _database.item(item_id) if not item_id.is_empty() and _database != null else null


func _clear_detail() -> void:
	item_icon.texture = null
	item_name.text = ""
	item_quantity.text = ""
	item_description.text = tr("UI_MENU_SELECT_ITEM")
	item_rules.text = ""
	use_button.disabled = true
	quick_button.disabled = true
	discard_button.disabled = true


func _refresh_category_labels() -> void:
	var labels := [
		"UI_MENU_ALL", "UI_MENU_CONSUMABLE", "UI_MENU_EQUIPMENT",
		"UI_MENU_KEY_ITEM", "UI_MENU_MATERIAL",
	]
	categories.clear()
	for key: String in labels:
		categories.add_item(tr(key))
	var category_index := _category + 1
	categories.select(clampi(category_index, 0, labels.size() - 1))
