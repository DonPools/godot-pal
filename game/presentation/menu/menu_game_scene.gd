class_name MenuGameScene
extends GameScene

@onready var status_label: Label = $UiLayer/Panel/Status
@onready var item_list: ItemList = $UiLayer/Panel/ItemList
@onready var hint_label: Label = $UiLayer/Panel/Hint
@onready var save_button: Button = $UiLayer/Panel/SaveButton
@onready var load_button: Button = $UiLayer/Panel/LoadButton
@onready var settings_button: Button = $UiLayer/Panel/SettingsButton
@onready var title_label: Label = $UiLayer/Panel/Title

var _database: ContentDatabase
var _game_run: GameRun
var _item_ids: Array[StringName] = []


func enter(context: GameSceneContext, _arguments: Variant) -> void:
	super.enter(context, _arguments)
	_database = context.content_database
	_game_run = context.game_run
	item_list.item_activated.connect(_use_item_at)
	save_button.pressed.connect(_open_save)
	load_button.pressed.connect(_open_load)
	settings_button.pressed.connect(_open_settings)
	_refresh()
	_refresh_text()
	if item_list.item_count > 0:
		item_list.select(0)
		item_list.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"menu"):
		scene_context.scene_stack.pop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"save_menu") and scene_context.save_load_scene != null:
		_open_save()
		get_viewport().set_input_as_handled()


func _open_save() -> void:
	if scene_context.save_load_scene != null:
		scene_context.scene_stack.push(scene_context.save_load_scene, {"save": true})


func _open_load() -> void:
	if scene_context.save_load_scene != null:
		scene_context.scene_stack.push(scene_context.save_load_scene, {"save": false})


func _open_settings() -> void:
	if scene_context.settings_scene != null:
		scene_context.scene_stack.push(scene_context.settings_scene)


func resume_scene(result: Variant = null) -> void:
	super.resume_scene(result)
	_refresh_text()


func _refresh_text() -> void:
	title_label.text = tr("UI_INVENTORY")
	save_button.text = tr("UI_SAVE")
	load_button.text = tr("UI_LOAD")
	settings_button.text = tr("UI_SETTINGS")


func _use_item_at(index: int) -> void:
	if index < 0 or index >= _item_ids.size():
		return
	var item := _database.item(_item_ids[index])
	var leader := _game_run.party.leader()
	var actor_definition := _database.actor(leader.definition_id) if leader != null else null
	if item is EquipmentDefinition:
		var equipment_result := EquipmentTransaction.equip(
			_game_run,
			leader,
			item as EquipmentDefinition,
			_database
		)
		match equipment_result.outcome:
			EquipmentResult.Outcome.EQUIPPED:
				hint_label.text = "装备了%s" % item.display_name
			EquipmentResult.Outcome.ALREADY_EQUIPPED:
				hint_label.text = "%s已经装备" % item.display_name
			EquipmentResult.Outcome.INVENTORY_REJECTED:
				hint_label.text = "背包无法收回原有法器"
			_:
				hint_label.text = "无法装备%s" % item.display_name
		_refresh(false)
		return
	var result := ItemUseTransaction.use_on_actor(
		_game_run,
		item,
		leader,
		actor_definition,
		_database
	)
	match result.outcome:
		ItemUseResult.Outcome.USED:
			hint_label.text = "使用了%s，恢复 %d" % [item.display_name, result.changed_amount]
		ItemUseResult.Outcome.NO_EFFECT:
			hint_label.text = "现在不需要使用%s" % item.display_name
		_:
			hint_label.text = "无法使用%s" % item.display_name
	_refresh(false)


func _refresh(reset_hint: bool = true) -> void:
	var leader := _game_run.party.leader()
	var actor_definition := _database.actor(leader.definition_id) if leader != null else null
	var realm := _database.realm(leader.realm_id) if leader != null else null
	var maximum_hp := CultivationRules.max_hp(actor_definition, leader, _database)
	var maximum_mp := CultivationRules.max_mp(actor_definition, leader, _database)
	var weapon_name := "无"
	if leader != null and leader.equipment.has(&"weapon"):
		var weapon := _database.item(leader.equipment[&"weapon"])
		if weapon != null:
			weapon_name = weapon.display_name
	status_label.text = (
		"%s  %s%d层  修为 %d  HP %d/%d  真气 %d/%d  法器 %s  钱 %d"
		% [
			actor_definition.display_name,
			realm.display_name,
			leader.realm_layer,
			leader.cultivation_points,
			leader.hp,
			maximum_hp,
			leader.mp,
			maximum_mp,
			weapon_name,
			_game_run.economy.money,
		]
		if leader != null and actor_definition != null and realm != null
		else "队伍为空"
	)
	item_list.clear()
	_item_ids.clear()
	for item_id: StringName in _game_run.inventory.item_ids():
		var item := _database.item(item_id)
		if item != null:
			_item_ids.append(item_id)
			item_list.add_item("%s  ×%d%s\n%s" % [
				item.display_name,
				_game_run.inventory.quantity(item_id),
				"　[法器]" if item is EquipmentDefinition else "",
				item.description,
			])
	if reset_hint:
		hint_label.text = "Enter 使用 · F6 保存 · Esc/M 关闭"
