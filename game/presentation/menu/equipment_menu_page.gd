class_name EquipmentMenuPage
extends MenuPage

@onready var slots: ItemList = $Slots
@onready var candidates: ItemList = $Candidates
@onready var equipment_icon: TextureRect = $Icon
@onready var equipment_name: Label = $Name
@onready var equipment_description: Label = $Description
@onready var comparison: Label = $Comparison
@onready var equip_button: Button = $Equip
@onready var unequip_button: Button = $Unequip

var _slot_ids: Array[StringName] = []
var _candidate_ids: Array[StringName] = []


func _ready() -> void:
	slots.item_selected.connect(select_slot)
	candidates.item_selected.connect(select_candidate)
	candidates.item_activated.connect(equip_selected_candidate)
	equip_button.pressed.connect(equip_selected_candidate)
	unequip_button.pressed.connect(unequip_selected_slot)


func refresh_text() -> void:
	equip_button.text = tr("UI_MENU_EQUIP")
	unequip_button.text = tr("UI_MENU_UNEQUIP")


func refresh() -> void:
	var previous_slot := selected_slot()
	slots.clear()
	_slot_ids.clear()
	var leader := _leader()
	var definition := _leader_definition()
	if leader == null or definition == null:
		_clear_detail()
		return
	for slot: StringName in definition.equipment_slots:
		_slot_ids.append(slot)
		var equipped := _database.item(leader.equipment.get(slot, &""))
		slots.add_item("%s：%s" % [
			_slot_display_name(slot),
			equipped.display_name if equipped != null else tr("UI_MENU_NONE"),
		], equipped.icon if equipped != null else null)
	if slots.item_count == 0:
		_clear_detail()
		return
	var selected := _slot_ids.find(previous_slot)
	selected = selected if selected >= 0 else 0
	slots.select(selected)
	select_slot(selected)


func initial_focus_control() -> Control:
	return slots


func selected_slot() -> StringName:
	var selected := slots.get_selected_items()
	return (
		_slot_ids[selected[0]]
		if not selected.is_empty() and selected[0] < _slot_ids.size()
		else &""
	)


func select_slot(index: int) -> void:
	if index < 0 or index >= _slot_ids.size():
		_clear_detail()
		return
	var previous_candidate := selected_candidate_id()
	var slot := _slot_ids[index]
	candidates.clear()
	_candidate_ids.clear()
	for item_id: StringName in _game_run.inventory.item_ids():
		var equipment := _database.item(item_id) as EquipmentDefinition
		if equipment == null or equipment.slot != slot:
			continue
		_candidate_ids.append(item_id)
		candidates.add_item(equipment.display_name, equipment.icon)
	var selected := _candidate_ids.find(previous_candidate)
	selected = selected if selected >= 0 else 0
	if candidates.item_count > 0:
		candidates.select(selected)
		select_candidate(selected)
	else:
		_show_current_equipment(slot)
	var leader := _leader()
	unequip_button.disabled = leader == null or not leader.equipment.has(slot)


func selected_candidate_id() -> StringName:
	var selected := candidates.get_selected_items()
	return (
		_candidate_ids[selected[0]]
		if not selected.is_empty() and selected[0] < _candidate_ids.size()
		else &""
	)


func select_candidate(index: int) -> void:
	if index < 0 or index >= _candidate_ids.size():
		_show_current_equipment(selected_slot())
		return
	var candidate := _database.item(_candidate_ids[index]) as EquipmentDefinition
	var leader := _leader()
	if candidate == null or leader == null:
		_clear_detail()
		return
	var current := _database.item(
		leader.equipment.get(candidate.slot, &"")
	) as EquipmentDefinition
	equipment_icon.texture = candidate.icon
	equipment_name.text = candidate.display_name
	equipment_description.text = candidate.description
	comparison.text = tr("UI_MENU_EQUIPMENT_COMPARE") % [
		_signed(candidate.max_hp_bonus - (current.max_hp_bonus if current != null else 0)),
		_signed(candidate.max_mp_bonus - (current.max_mp_bonus if current != null else 0)),
		_signed(candidate.attack_bonus - (current.attack_bonus if current != null else 0)),
	]
	equip_button.disabled = false


func equip_selected_candidate(_index: int = -1) -> void:
	var equipment := _database.item(selected_candidate_id()) as EquipmentDefinition
	if equipment == null:
		return
	var result := EquipmentTransaction.equip(_game_run, _leader(), equipment, _database)
	_request_equipment_result_hint(result, equipment)
	content_changed.emit()


func unequip_selected_slot() -> void:
	var result := EquipmentTransaction.unequip(
		_game_run, _leader(), selected_slot(), _database
	)
	match result.outcome:
		EquipmentResult.Outcome.UNEQUIPPED:
			var returned := _database.item(result.returned_item_id)
			hint_requested.emit(
				tr("UI_MENU_UNEQUIPPED")
				% (
					returned.display_name
					if returned != null
					else String(result.returned_item_id)
				)
			)
		EquipmentResult.Outcome.INVENTORY_REJECTED:
			hint_requested.emit(tr("UI_MENU_INVENTORY_REJECTED"))
		_:
			hint_requested.emit(tr("UI_MENU_UNEQUIP_FAILED"))
	content_changed.emit()


func _show_current_equipment(slot: StringName) -> void:
	var leader := _leader()
	var current := _database.item(leader.equipment.get(slot, &"")) if leader != null else null
	if current == null:
		_clear_detail()
		equipment_description.text = tr("UI_MENU_NO_EQUIPMENT_CANDIDATE")
		unequip_button.disabled = true
		return
	equipment_icon.texture = current.icon
	equipment_name.text = current.display_name
	equipment_description.text = current.description
	comparison.text = tr("UI_MENU_CURRENT_EQUIPMENT")
	equip_button.disabled = true
	unequip_button.disabled = false


func _clear_detail() -> void:
	equipment_icon.texture = null
	equipment_name.text = ""
	equipment_description.text = tr("UI_MENU_SELECT_EQUIPMENT")
	comparison.text = ""
	equip_button.disabled = true
	unequip_button.disabled = true


func _slot_display_name(slot: StringName) -> String:
	return tr("UI_MENU_WEAPON_SLOT") if slot == &"weapon" else String(slot)


func _signed(value: int) -> String:
	return "%+d" % value
