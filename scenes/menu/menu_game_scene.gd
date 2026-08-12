class_name MenuGameScene
extends GameScene

@onready var status_label: Label = $UiLayer/Panel/Status
@onready var item_list: ItemList = $UiLayer/Panel/ItemList
@onready var hint_label: Label = $UiLayer/Panel/Hint

var _database: ContentDatabase
var _game_run: GameRun
var _item_ids: Array[StringName] = []


func enter(context: GameSceneContext, _arguments: Variant) -> void:
	super.enter(context, _arguments)
	_database = context.content_database
	_game_run = context.game_run
	item_list.item_activated.connect(_use_item_at)
	_refresh()
	if item_list.item_count > 0:
		item_list.select(0)
		item_list.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"menu"):
		scene_context.scene_stack.pop()
		get_viewport().set_input_as_handled()


func _use_item_at(index: int) -> void:
	if index < 0 or index >= _item_ids.size():
		return
	var item := _database.item(_item_ids[index])
	var leader := _game_run.party.leader()
	var actor_definition := _database.actor(leader.definition_id) if leader != null else null
	var result := ItemUseTransaction.use_on_actor(_game_run, item, leader, actor_definition)
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
	status_label.text = (
		"%s  Lv.%d  HP %d/%d  MP %d/%d  钱 %d"
		% [
			actor_definition.display_name,
			leader.level,
			leader.hp,
			actor_definition.base_max_hp,
			leader.mp,
			actor_definition.base_max_mp,
			_game_run.economy.money,
		]
		if leader != null and actor_definition != null
		else "队伍为空"
	)
	item_list.clear()
	_item_ids.clear()
	for item_id: StringName in _game_run.inventory.item_ids():
		var item := _database.item(item_id)
		if item != null:
			_item_ids.append(item_id)
			item_list.add_item("%s  ×%d\n%s" % [
				item.display_name,
				_game_run.inventory.quantity(item_id),
				item.description,
			])
	if reset_hint:
		hint_label.text = "Enter 使用 · Esc/M 关闭"
