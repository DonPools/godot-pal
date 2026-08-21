class_name MenuGameScene
extends GameScene

enum Page {
	STATUS,
	INVENTORY,
	EQUIPMENT,
	SKILLS,
	SYSTEM,
}

const ALL_CATEGORIES := -1

@onready var title_label: Label = $UiLayer/Panel/Title
@onready var hint_label: Label = $UiLayer/Panel/Hint
@onready var _tab_buttons: Array[Button] = [
	$UiLayer/Panel/Tabs/Status,
	$UiLayer/Panel/Tabs/Inventory,
	$UiLayer/Panel/Tabs/Equipment,
	$UiLayer/Panel/Tabs/Skills,
	$UiLayer/Panel/Tabs/System,
]
@onready var _pages: Array[Control] = [
	$UiLayer/Panel/Pages/StatusPage,
	$UiLayer/Panel/Pages/InventoryPage,
	$UiLayer/Panel/Pages/EquipmentPage,
	$UiLayer/Panel/Pages/SkillsPage,
	$UiLayer/Panel/Pages/SystemPage,
]

@onready var status_summary: Label = $UiLayer/Panel/Pages/StatusPage/Summary

@onready var inventory_categories: ItemList = $UiLayer/Panel/Pages/InventoryPage/Categories
@onready var inventory_capacity: Label = $UiLayer/Panel/Pages/InventoryPage/Capacity
@onready var inventory_items: ItemList = $UiLayer/Panel/Pages/InventoryPage/Items
@onready var inventory_empty: Label = $UiLayer/Panel/Pages/InventoryPage/Empty
@onready var inventory_icon: TextureRect = $UiLayer/Panel/Pages/InventoryPage/Icon
@onready var inventory_name: Label = $UiLayer/Panel/Pages/InventoryPage/Name
@onready var inventory_quantity: Label = $UiLayer/Panel/Pages/InventoryPage/Quantity
@onready var inventory_description: Label = $UiLayer/Panel/Pages/InventoryPage/Description
@onready var inventory_rules: Label = $UiLayer/Panel/Pages/InventoryPage/Rules
@onready var inventory_use: Button = $UiLayer/Panel/Pages/InventoryPage/Use
@onready var inventory_quick: Button = $UiLayer/Panel/Pages/InventoryPage/Quick
@onready var inventory_discard: Button = $UiLayer/Panel/Pages/InventoryPage/Discard

@onready var equipment_slots: ItemList = $UiLayer/Panel/Pages/EquipmentPage/Slots
@onready var equipment_candidates: ItemList = $UiLayer/Panel/Pages/EquipmentPage/Candidates
@onready var equipment_icon: TextureRect = $UiLayer/Panel/Pages/EquipmentPage/Icon
@onready var equipment_name: Label = $UiLayer/Panel/Pages/EquipmentPage/Name
@onready var equipment_description: Label = $UiLayer/Panel/Pages/EquipmentPage/Description
@onready var equipment_comparison: Label = $UiLayer/Panel/Pages/EquipmentPage/Comparison
@onready var equipment_equip: Button = $UiLayer/Panel/Pages/EquipmentPage/Equip
@onready var equipment_unequip: Button = $UiLayer/Panel/Pages/EquipmentPage/Unequip

@onready var learned_skills: ItemList = $UiLayer/Panel/Pages/SkillsPage/Known
@onready var skill_detail: Label = $UiLayer/Panel/Pages/SkillsPage/Detail
@onready var skill_slot_buttons: Array[Button] = [
	$UiLayer/Panel/Pages/SkillsPage/SkillSlot1,
	$UiLayer/Panel/Pages/SkillsPage/SkillSlot2,
	$UiLayer/Panel/Pages/SkillsPage/SkillSlot3,
]
@onready var skill_clear_buttons: Array[Button] = [
	$UiLayer/Panel/Pages/SkillsPage/ClearSkill1,
	$UiLayer/Panel/Pages/SkillsPage/ClearSkill2,
	$UiLayer/Panel/Pages/SkillsPage/ClearSkill3,
]

@onready var system_summary: Label = $UiLayer/Panel/Pages/SystemPage/Summary
@onready var save_button: Button = $UiLayer/Panel/Pages/SystemPage/Save
@onready var load_button: Button = $UiLayer/Panel/Pages/SystemPage/Load
@onready var settings_button: Button = $UiLayer/Panel/Pages/SystemPage/Settings
@onready var return_title_button: Button = $UiLayer/Panel/Pages/SystemPage/ReturnTitle

@onready var discard_dialog: ConfirmationDialog = $DiscardDialog
@onready var discard_prompt: Label = $DiscardDialog/Prompt
@onready var discard_quantity: SpinBox = $DiscardDialog/Quantity

var _database: ContentDatabase
var _game_run: GameRun
var _current_page: Page = Page.STATUS
var _category: int = ALL_CATEGORIES
var _inventory_item_ids: Array[StringName] = []
var _equipment_slot_ids: Array[StringName] = []
var _equipment_candidate_ids: Array[StringName] = []
var _learned_skill_ids: Array[StringName] = []
var _pending_discard_item_id: StringName
var _resume_focus: Control


func enter(context: GameSceneContext, _arguments: Variant) -> void:
	super.enter(context, _arguments)
	_database = context.content_database
	_game_run = context.game_run
	for index: int in range(_tab_buttons.size()):
		_tab_buttons[index].pressed.connect(_show_page.bind(index, true))
	inventory_categories.item_selected.connect(_select_inventory_category)
	inventory_items.item_selected.connect(_select_inventory_item)
	inventory_items.item_activated.connect(_activate_inventory_item)
	inventory_use.pressed.connect(_use_selected_inventory_item)
	inventory_quick.pressed.connect(_assign_selected_quick_item)
	inventory_discard.pressed.connect(_request_discard_selected_item)
	equipment_slots.item_selected.connect(_select_equipment_slot)
	equipment_candidates.item_selected.connect(_select_equipment_candidate)
	equipment_candidates.item_activated.connect(_equip_selected_candidate)
	equipment_equip.pressed.connect(_equip_selected_candidate)
	equipment_unequip.pressed.connect(_unequip_selected_slot)
	learned_skills.item_selected.connect(_select_learned_skill)
	for index: int in range(skill_slot_buttons.size()):
		skill_slot_buttons[index].pressed.connect(_assign_selected_skill.bind(index))
		skill_clear_buttons[index].pressed.connect(_clear_skill_slot.bind(index))
	save_button.pressed.connect(_open_save)
	load_button.pressed.connect(_open_load)
	settings_button.pressed.connect(_open_settings)
	return_title_button.pressed.connect(_return_to_title)
	discard_dialog.confirmed.connect(_confirm_discard)
	_refresh_text()
	_refresh_all()
	_show_page(Page.STATUS, true)
	hint_label.text = tr("UI_MENU_HINT_BACK")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel") and not event.is_action_pressed(&"menu"):
		return
	if discard_dialog.visible:
		discard_dialog.hide()
	else:
		scene_context.scene_stack.pop()
	get_viewport().set_input_as_handled()


func resume_scene(result: Variant = null) -> void:
	super.resume_scene(result)
	_game_run = scene_context.game_run
	_refresh_text()
	_refresh_all()
	_show_page(_current_page, false)
	if is_instance_valid(_resume_focus) and _resume_focus.is_visible_in_tree():
		_resume_focus.grab_focus()
	else:
		_focus_page()
	_resume_focus = null
	hint_label.text = tr("UI_MENU_HINT_BACK")


func _refresh_text() -> void:
	title_label.text = tr("UI_MENU_TITLE")
	var tab_keys := [
		"UI_MENU_STATUS", "UI_MENU_INVENTORY", "UI_MENU_EQUIPMENT",
		"UI_MENU_SKILLS", "UI_MENU_SYSTEM",
	]
	for index: int in range(_tab_buttons.size()):
		_tab_buttons[index].text = tr(tab_keys[index])
	inventory_empty.text = tr("UI_MENU_CATEGORY_EMPTY")
	inventory_use.text = tr("UI_MENU_USE")
	inventory_quick.text = tr("UI_MENU_SET_QUICK")
	inventory_discard.text = tr("UI_MENU_DISCARD")
	equipment_equip.text = tr("UI_MENU_EQUIP")
	equipment_unequip.text = tr("UI_MENU_UNEQUIP")
	system_summary.text = tr("UI_MENU_SYSTEM_SUMMARY")
	save_button.text = tr("UI_SAVE")
	load_button.text = tr("UI_LOAD")
	settings_button.text = tr("UI_SETTINGS")
	return_title_button.text = tr("UI_MENU_RETURN_TITLE")
	discard_dialog.title = tr("UI_MENU_DISCARD_TITLE")
	discard_dialog.ok_button_text = tr("UI_MENU_DISCARD_CONFIRM")
	discard_dialog.cancel_button_text = tr("UI_MENU_CANCEL")
	_refresh_category_labels()


func _refresh_category_labels() -> void:
	var labels := [
		"UI_MENU_ALL", "UI_MENU_CONSUMABLE", "UI_MENU_EQUIPMENT",
		"UI_MENU_KEY_ITEM", "UI_MENU_MATERIAL",
	]
	inventory_categories.clear()
	for key: String in labels:
		inventory_categories.add_item(tr(key))
	var category_index := _category + 1
	inventory_categories.select(clampi(category_index, 0, labels.size() - 1))


func _show_page(page_index: int, focus_page: bool) -> void:
	_current_page = page_index as Page
	for index: int in range(_pages.size()):
		_pages[index].visible = index == page_index
		_tab_buttons[index].button_pressed = index == page_index
	_refresh_page()
	if focus_page:
		_focus_page()


func _refresh_page() -> void:
	match _current_page:
		Page.STATUS:
			_refresh_status()
		Page.INVENTORY:
			_refresh_inventory()
		Page.EQUIPMENT:
			_refresh_equipment()
		Page.SKILLS:
			_refresh_skills()


func _focus_page() -> void:
	match _current_page:
		Page.INVENTORY:
			(inventory_items if inventory_items.item_count > 0 else inventory_categories).grab_focus()
		Page.EQUIPMENT:
			equipment_slots.grab_focus()
		Page.SKILLS:
			(learned_skills if learned_skills.item_count > 0 else skill_slot_buttons[0]).grab_focus()
		Page.SYSTEM:
			save_button.grab_focus()
		_:
			_tab_buttons[int(_current_page)].grab_focus()


func _refresh_all() -> void:
	_refresh_status()
	_refresh_inventory()
	_refresh_equipment()
	_refresh_skills()


func _leader() -> ActorState:
	return _game_run.party.leader() if _game_run != null else null


func _leader_definition() -> ActorDefinition:
	var leader := _leader()
	return _database.actor(leader.definition_id) if leader != null and _database != null else null


func _refresh_status() -> void:
	var leader := _leader()
	var definition := _leader_definition()
	if leader == null or definition == null:
		status_summary.text = tr("UI_MENU_PARTY_EMPTY")
		return
	var realm := _database.realm(leader.realm_id)
	var foundation := _database.foundation(leader.foundation_id)
	var equipment := _database.item(leader.equipment.get(&"weapon", &""))
	status_summary.text = tr("UI_MENU_STATUS_FORMAT") % [
		definition.display_name,
		realm.display_name if realm != null else String(leader.realm_id),
		leader.realm_layer,
		leader.cultivation_points,
		foundation.display_name if foundation != null else tr("UI_MENU_NONE"),
		leader.hp,
		CultivationRules.max_hp(definition, leader, _database),
		leader.mp,
		CultivationRules.max_mp(definition, leader, _database),
		CultivationRules.attack(definition, leader, _database),
		equipment.display_name if equipment != null else tr("UI_MENU_NONE"),
		_game_run.economy.money,
	]


func _select_inventory_category(index: int) -> void:
	_category = index - 1
	_refresh_inventory()
	if inventory_items.item_count > 0:
		inventory_items.grab_focus()


func _refresh_inventory() -> void:
	var previous_id := _selected_inventory_item_id()
	inventory_items.clear()
	_inventory_item_ids.clear()
	if _game_run == null or _database == null:
		_clear_inventory_detail()
		return
	for item_id: StringName in _game_run.inventory.item_ids():
		var item := _database.item(item_id)
		if item == null or (_category >= 0 and int(item.category) != _category):
			continue
		_inventory_item_ids.append(item_id)
		inventory_items.add_item(
			"%s  ×%d" % [item.display_name, _game_run.inventory.quantity(item_id)],
			item.icon
		)
	inventory_capacity.text = tr("UI_MENU_CAPACITY") % [
		_game_run.inventory.occupied_capacity(),
		_game_run.inventory.max_distinct_items,
	]
	inventory_empty.visible = inventory_items.item_count == 0
	if inventory_items.item_count == 0:
		_clear_inventory_detail()
		return
	var selected := _inventory_item_ids.find(previous_id)
	selected = selected if selected >= 0 else 0
	inventory_items.select(selected)
	_select_inventory_item(selected)


func _selected_inventory_item_id() -> StringName:
	var selected := inventory_items.get_selected_items()
	return (
		_inventory_item_ids[selected[0]]
		if not selected.is_empty() and selected[0] < _inventory_item_ids.size()
		else &""
	)


func _selected_inventory_item() -> ItemDefinition:
	var item_id := _selected_inventory_item_id()
	return _database.item(item_id) if not item_id.is_empty() and _database != null else null


func _select_inventory_item(index: int) -> void:
	if index < 0 or index >= _inventory_item_ids.size():
		_clear_inventory_detail()
		return
	var item := _database.item(_inventory_item_ids[index])
	if item == null:
		_clear_inventory_detail()
		return
	inventory_icon.texture = item.icon
	inventory_name.text = item.display_name
	inventory_quantity.text = tr("UI_MENU_QUANTITY") % _game_run.inventory.quantity(item.id)
	inventory_description.text = item.description
	var scope := tr("UI_MENU_FIELD_AND_BATTLE") if item.usable_in_field and item.usable_in_battle else tr("UI_MENU_FIELD_ONLY") if item.usable_in_field else tr("UI_MENU_BATTLE_ONLY") if item.usable_in_battle else tr("UI_MENU_NOT_USABLE")
	inventory_rules.text = "%s · %s" % [scope, tr("UI_MENU_KEY_CAPACITY_FREE") if item.category == ItemDefinition.Category.KEY_ITEM else tr("UI_MENU_USES_CAPACITY")]
	inventory_use.text = tr("UI_MENU_EQUIP") if item is EquipmentDefinition else tr("UI_MENU_USE")
	inventory_use.disabled = not item is EquipmentDefinition and not item.usable_in_field
	inventory_quick.disabled = not item.usable_in_battle or _game_run.inventory.quantity(item.id) <= 0
	inventory_discard.disabled = not item.can_discard


func _clear_inventory_detail() -> void:
	inventory_icon.texture = null
	inventory_name.text = ""
	inventory_quantity.text = ""
	inventory_description.text = tr("UI_MENU_SELECT_ITEM")
	inventory_rules.text = ""
	inventory_use.disabled = true
	inventory_quick.disabled = true
	inventory_discard.disabled = true


func _activate_inventory_item(index: int) -> void:
	if index >= 0 and index < _inventory_item_ids.size():
		inventory_items.select(index)
		_use_selected_inventory_item()


func _use_selected_inventory_item() -> void:
	var item := _selected_inventory_item()
	var leader := _leader()
	var definition := _leader_definition()
	if item == null or leader == null or definition == null:
		return
	if item is EquipmentDefinition:
		var equipment_result := EquipmentTransaction.equip(
			_game_run, leader, item as EquipmentDefinition, _database
		)
		_show_equipment_result(equipment_result, item)
	else:
		var result := ItemUseTransaction.use_on_actor(
			_game_run, item, leader, definition, _database
		)
		match result.outcome:
			ItemUseResult.Outcome.USED:
				_show_hint(tr("UI_MENU_USED") % [item.display_name, result.changed_amount])
			ItemUseResult.Outcome.NO_EFFECT:
				_show_hint(tr("UI_MENU_NO_EFFECT") % item.display_name)
			_:
				_show_hint(tr("UI_MENU_CANNOT_USE") % item.display_name)
	_refresh_all()


func _assign_selected_quick_item() -> void:
	var item := _selected_inventory_item()
	var result := BattleItemLoadoutTransaction.assign(
		_game_run, _leader(), item, _database
	)
	match result.outcome:
		BattleItemLoadoutResult.Outcome.ASSIGNED:
			_show_hint(tr("UI_MENU_QUICK_ASSIGNED") % item.display_name)
		BattleItemLoadoutResult.Outcome.UNCHANGED:
			_show_hint(tr("UI_MENU_QUICK_UNCHANGED") % item.display_name)
		_:
			_show_hint(tr("UI_MENU_QUICK_FAILED"))
	_refresh_all()


func _request_discard_selected_item() -> void:
	var item := _selected_inventory_item()
	if item == null or not item.can_discard:
		return
	_pending_discard_item_id = item.id
	discard_prompt.text = tr("UI_MENU_DISCARD_PROMPT") % item.display_name
	discard_quantity.max_value = _game_run.inventory.quantity(item.id)
	discard_quantity.value = 1
	discard_dialog.popup_centered()


func _confirm_discard() -> void:
	var item := _database.item(_pending_discard_item_id)
	var quantity := int(discard_quantity.value)
	var result := ItemDiscardTransaction.discard(_game_run, item, quantity)
	if result.succeeded():
		_show_hint(tr("UI_MENU_DISCARDED") % [item.display_name, quantity])
	else:
		_show_hint(tr("UI_MENU_DISCARD_FAILED"))
	_pending_discard_item_id = &""
	_refresh_all()


func _refresh_equipment() -> void:
	var previous_slot := _selected_equipment_slot()
	equipment_slots.clear()
	_equipment_slot_ids.clear()
	var leader := _leader()
	var definition := _leader_definition()
	if leader == null or definition == null:
		_clear_equipment_detail()
		return
	for slot: StringName in definition.equipment_slots:
		_equipment_slot_ids.append(slot)
		var equipped := _database.item(leader.equipment.get(slot, &""))
		equipment_slots.add_item("%s：%s" % [
			_slot_display_name(slot),
			equipped.display_name if equipped != null else tr("UI_MENU_NONE"),
		], equipped.icon if equipped != null else null)
	if equipment_slots.item_count == 0:
		_clear_equipment_detail()
		return
	var selected := _equipment_slot_ids.find(previous_slot)
	selected = selected if selected >= 0 else 0
	equipment_slots.select(selected)
	_select_equipment_slot(selected)


func _selected_equipment_slot() -> StringName:
	var selected := equipment_slots.get_selected_items()
	return (
		_equipment_slot_ids[selected[0]]
		if not selected.is_empty() and selected[0] < _equipment_slot_ids.size()
		else &""
	)


func _select_equipment_slot(index: int) -> void:
	if index < 0 or index >= _equipment_slot_ids.size():
		_clear_equipment_detail()
		return
	var previous_candidate := _selected_equipment_candidate_id()
	var slot := _equipment_slot_ids[index]
	equipment_candidates.clear()
	_equipment_candidate_ids.clear()
	for item_id: StringName in _game_run.inventory.item_ids():
		var equipment := _database.item(item_id) as EquipmentDefinition
		if equipment == null or equipment.slot != slot:
			continue
		_equipment_candidate_ids.append(item_id)
		equipment_candidates.add_item(equipment.display_name, equipment.icon)
	var selected := _equipment_candidate_ids.find(previous_candidate)
	selected = selected if selected >= 0 else 0
	if equipment_candidates.item_count > 0:
		equipment_candidates.select(selected)
		_select_equipment_candidate(selected)
	else:
		_show_current_equipment(slot)
	var leader := _leader()
	equipment_unequip.disabled = leader == null or not leader.equipment.has(slot)


func _selected_equipment_candidate_id() -> StringName:
	var selected := equipment_candidates.get_selected_items()
	return (
		_equipment_candidate_ids[selected[0]]
		if not selected.is_empty() and selected[0] < _equipment_candidate_ids.size()
		else &""
	)


func _select_equipment_candidate(index: int) -> void:
	if index < 0 or index >= _equipment_candidate_ids.size():
		_show_current_equipment(_selected_equipment_slot())
		return
	var candidate := _database.item(_equipment_candidate_ids[index]) as EquipmentDefinition
	var leader := _leader()
	if candidate == null or leader == null:
		_clear_equipment_detail()
		return
	var current := _database.item(leader.equipment.get(candidate.slot, &"")) as EquipmentDefinition
	equipment_icon.texture = candidate.icon
	equipment_name.text = candidate.display_name
	equipment_description.text = candidate.description
	equipment_comparison.text = tr("UI_MENU_EQUIPMENT_COMPARE") % [
		_signed(candidate.max_hp_bonus - (current.max_hp_bonus if current != null else 0)),
		_signed(candidate.max_mp_bonus - (current.max_mp_bonus if current != null else 0)),
		_signed(candidate.attack_bonus - (current.attack_bonus if current != null else 0)),
	]
	equipment_equip.disabled = false


func _show_current_equipment(slot: StringName) -> void:
	var leader := _leader()
	var current := _database.item(leader.equipment.get(slot, &"")) if leader != null else null
	if current == null:
		_clear_equipment_detail()
		equipment_description.text = tr("UI_MENU_NO_EQUIPMENT_CANDIDATE")
		equipment_unequip.disabled = true
		return
	equipment_icon.texture = current.icon
	equipment_name.text = current.display_name
	equipment_description.text = current.description
	equipment_comparison.text = tr("UI_MENU_CURRENT_EQUIPMENT")
	equipment_equip.disabled = true
	equipment_unequip.disabled = false


func _clear_equipment_detail() -> void:
	equipment_icon.texture = null
	equipment_name.text = ""
	equipment_description.text = tr("UI_MENU_SELECT_EQUIPMENT")
	equipment_comparison.text = ""
	equipment_equip.disabled = true
	equipment_unequip.disabled = true


func _equip_selected_candidate(_index: int = -1) -> void:
	var equipment := _database.item(_selected_equipment_candidate_id()) as EquipmentDefinition
	if equipment == null:
		return
	var result := EquipmentTransaction.equip(_game_run, _leader(), equipment, _database)
	_show_equipment_result(result, equipment)
	_refresh_all()


func _unequip_selected_slot() -> void:
	var slot := _selected_equipment_slot()
	var result := EquipmentTransaction.unequip(_game_run, _leader(), slot, _database)
	match result.outcome:
		EquipmentResult.Outcome.UNEQUIPPED:
			var returned := _database.item(result.returned_item_id)
			_show_hint(tr("UI_MENU_UNEQUIPPED") % (returned.display_name if returned != null else String(result.returned_item_id)))
		EquipmentResult.Outcome.INVENTORY_REJECTED:
			_show_hint(tr("UI_MENU_INVENTORY_REJECTED"))
		_:
			_show_hint(tr("UI_MENU_UNEQUIP_FAILED"))
	_refresh_all()


func _show_equipment_result(result: EquipmentResult, equipment: ItemDefinition) -> void:
	match result.outcome:
		EquipmentResult.Outcome.EQUIPPED:
			_show_hint(tr("UI_MENU_EQUIPPED") % equipment.display_name)
		EquipmentResult.Outcome.ALREADY_EQUIPPED:
			_show_hint(tr("UI_MENU_ALREADY_EQUIPPED") % equipment.display_name)
		EquipmentResult.Outcome.INVENTORY_REJECTED:
			_show_hint(tr("UI_MENU_INVENTORY_REJECTED"))
		EquipmentResult.Outcome.SLOT_NOT_ALLOWED:
			_show_hint(tr("UI_MENU_SLOT_NOT_ALLOWED"))
		_:
			_show_hint(tr("UI_MENU_EQUIP_FAILED") % equipment.display_name)


func _refresh_skills() -> void:
	var previous_id := _selected_learned_skill_id()
	learned_skills.clear()
	_learned_skill_ids.clear()
	var leader := _leader()
	if leader == null:
		skill_detail.text = tr("UI_MENU_PARTY_EMPTY")
		return
	for skill_id: StringName in leader.learned_skill_ids:
		var skill := _database.skill(skill_id)
		if skill == null:
			continue
		_learned_skill_ids.append(skill_id)
		learned_skills.add_item(skill.display_name, skill.icon)
	if learned_skills.item_count > 0:
		var selected := _learned_skill_ids.find(previous_id)
		selected = selected if selected >= 0 else 0
		learned_skills.select(selected)
		_select_learned_skill(selected)
	else:
		skill_detail.text = tr("UI_MENU_NO_SKILLS")
	_refresh_skill_slots()


func _selected_learned_skill_id() -> StringName:
	var selected := learned_skills.get_selected_items()
	return (
		_learned_skill_ids[selected[0]]
		if not selected.is_empty() and selected[0] < _learned_skill_ids.size()
		else &""
	)


func _select_learned_skill(index: int) -> void:
	if index < 0 or index >= _learned_skill_ids.size():
		skill_detail.text = tr("UI_MENU_SELECT_SKILL")
		return
	var skill := _database.skill(_learned_skill_ids[index])
	skill_detail.text = tr("UI_MENU_SKILL_DETAIL") % [
		skill.display_name,
		skill.mp_cost,
		skill.cooldown_seconds,
		_skill_target_name(skill.target_rule),
		skill.max_range,
		skill.radius,
		skill.description,
	]


func _refresh_skill_slots() -> void:
	var leader := _leader()
	for index: int in range(skill_slot_buttons.size()):
		var skill_id := leader.battle_skill_ids[index] if leader != null else &""
		var skill := _database.skill(skill_id) if not skill_id.is_empty() else null
		skill_slot_buttons[index].text = "%d · %s" % [
			index + 1,
			skill.display_name if skill != null else tr("UI_MENU_NOT_CONFIGURED"),
		]
		skill_slot_buttons[index].icon = skill.icon if skill != null else null
		skill_clear_buttons[index].disabled = skill == null


func _assign_selected_skill(slot_index: int) -> void:
	var skill := _database.skill(_selected_learned_skill_id())
	var result := SkillLoadoutTransaction.assign(_leader(), skill, slot_index, _database)
	match result.outcome:
		SkillLoadoutResult.Outcome.ASSIGNED:
			_show_hint(tr("UI_MENU_SKILL_ASSIGNED") % [skill.display_name, slot_index + 1])
		SkillLoadoutResult.Outcome.UNCHANGED:
			_show_hint(tr("UI_MENU_SKILL_UNCHANGED"))
		_:
			_show_hint(tr("UI_MENU_SKILL_ASSIGN_FAILED"))
	_refresh_skills()


func _clear_skill_slot(slot_index: int) -> void:
	var result := SkillLoadoutTransaction.clear(_leader(), slot_index)
	if result.outcome == SkillLoadoutResult.Outcome.CLEARED:
		_show_hint(tr("UI_MENU_SKILL_CLEARED") % (slot_index + 1))
	else:
		_show_hint(tr("UI_MENU_SKILL_UNCHANGED"))
	_refresh_skills()


func _open_save() -> void:
	if scene_context.save_load_scene != null:
		_resume_focus = save_button
		scene_context.scene_stack.push(scene_context.save_load_scene, {"save": true})


func _open_load() -> void:
	if scene_context.save_load_scene != null:
		_resume_focus = load_button
		scene_context.scene_stack.push(scene_context.save_load_scene, {"save": false})


func _open_settings() -> void:
	if scene_context.settings_scene != null:
		_resume_focus = settings_button
		scene_context.scene_stack.push(scene_context.settings_scene)


func _return_to_title() -> void:
	if scene_context.return_to_title.is_valid():
		scene_context.return_to_title.call()


func _show_hint(message: String) -> void:
	hint_label.text = message


func _slot_display_name(slot: StringName) -> String:
	return tr("UI_MENU_WEAPON_SLOT") if slot == &"weapon" else String(slot)


func _skill_target_name(target_rule: SkillDefinition.TargetRule) -> String:
	match target_rule:
		SkillDefinition.TargetRule.SELF:
			return tr("UI_MENU_SKILL_TARGET_SELF")
		SkillDefinition.TargetRule.SINGLE_ENEMY:
			return tr("UI_MENU_SKILL_TARGET_SINGLE_ENEMY")
		SkillDefinition.TargetRule.DIRECTION:
			return tr("UI_MENU_SKILL_TARGET_DIRECTION")
		SkillDefinition.TargetRule.POINT:
			return tr("UI_MENU_SKILL_TARGET_POINT")
		SkillDefinition.TargetRule.AREA:
			return tr("UI_MENU_SKILL_TARGET_AREA")
	return tr("UI_MENU_SKILL_TARGET_UNKNOWN")


func _signed(value: int) -> String:
	return "%+d" % value
