class_name SkillsMenuPage
extends MenuPage

@onready var learned_skills: ItemList = $Known
@onready var detail: Label = $Detail
@onready var slot_buttons: Array[Button] = [
	$SkillSlot1,
	$SkillSlot2,
	$SkillSlot3,
]
@onready var clear_buttons: Array[Button] = [
	$ClearSkill1,
	$ClearSkill2,
	$ClearSkill3,
]

var _learned_skill_ids: Array[StringName] = []


func _ready() -> void:
	learned_skills.item_selected.connect(select_learned_skill)
	for index: int in range(slot_buttons.size()):
		slot_buttons[index].pressed.connect(assign_selected_skill.bind(index))
		clear_buttons[index].pressed.connect(clear_skill_slot.bind(index))


func refresh() -> void:
	var previous_id := selected_learned_skill_id()
	learned_skills.clear()
	_learned_skill_ids.clear()
	var leader := _leader()
	if leader == null:
		detail.text = tr("UI_MENU_PARTY_EMPTY")
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
		select_learned_skill(selected)
	else:
		detail.text = tr("UI_MENU_NO_SKILLS")
	_refresh_slots()


func initial_focus_control() -> Control:
	return learned_skills if learned_skills.item_count > 0 else slot_buttons[0]


func selected_learned_skill_id() -> StringName:
	var selected := learned_skills.get_selected_items()
	return (
		_learned_skill_ids[selected[0]]
		if not selected.is_empty() and selected[0] < _learned_skill_ids.size()
		else &""
	)


func select_learned_skill(index: int) -> void:
	if index < 0 or index >= _learned_skill_ids.size():
		detail.text = tr("UI_MENU_SELECT_SKILL")
		return
	var skill := _database.skill(_learned_skill_ids[index])
	detail.text = tr("UI_MENU_SKILL_DETAIL") % [
		skill.display_name,
		skill.mp_cost,
		skill.cooldown_seconds,
		_skill_target_name(skill.target_rule),
		skill.max_range,
		skill.radius,
		skill.description,
	]


func assign_selected_skill(slot_index: int) -> void:
	var skill := _database.skill(selected_learned_skill_id())
	if skill == null:
		hint_requested.emit(tr("UI_MENU_SKILL_ASSIGN_FAILED"))
		return
	var result := SkillLoadoutTransaction.assign(_leader(), skill, slot_index, _database)
	match result.outcome:
		SkillLoadoutResult.Outcome.ASSIGNED:
			hint_requested.emit(
				tr("UI_MENU_SKILL_ASSIGNED") % [skill.display_name, slot_index + 1]
			)
		SkillLoadoutResult.Outcome.UNCHANGED:
			hint_requested.emit(tr("UI_MENU_SKILL_UNCHANGED"))
		_:
			hint_requested.emit(tr("UI_MENU_SKILL_ASSIGN_FAILED"))
	content_changed.emit()


func clear_skill_slot(slot_index: int) -> void:
	var result := SkillLoadoutTransaction.clear(_leader(), slot_index)
	if result.outcome == SkillLoadoutResult.Outcome.CLEARED:
		hint_requested.emit(tr("UI_MENU_SKILL_CLEARED") % (slot_index + 1))
	else:
		hint_requested.emit(tr("UI_MENU_SKILL_UNCHANGED"))
	content_changed.emit()


func _refresh_slots() -> void:
	var leader := _leader()
	for index: int in range(slot_buttons.size()):
		var skill_id := leader.battle_skill_ids[index] if leader != null else &""
		var skill := _database.skill(skill_id) if not skill_id.is_empty() else null
		slot_buttons[index].text = "%d · %s" % [
			index + 1,
			skill.display_name if skill != null else tr("UI_MENU_NOT_CONFIGURED"),
		]
		slot_buttons[index].icon = skill.icon if skill != null else null
		clear_buttons[index].disabled = skill == null


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
