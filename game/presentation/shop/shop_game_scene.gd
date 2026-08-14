class_name ShopGameScene
extends GameScene

@onready var title_label: Label = $UiLayer/Panel/Title
@onready var money_label: Label = $UiLayer/Panel/Money
@onready var item_list: ItemList = $UiLayer/Panel/ItemList
@onready var hint_label: Label = $UiLayer/Panel/Hint

var _shop: ShopDefinition
var _last_result := ShopResult.new()


func enter(context: GameSceneContext, arguments: Variant) -> void:
	super.enter(context, arguments)
	_shop = arguments as ShopDefinition
	if _shop == null:
		push_error("ShopGameScene requires a ShopDefinition")
		context.scene_stack.pop(_last_result)
		return
	title_label.text = _shop.display_name
	item_list.item_activated.connect(_buy_at)
	_refresh()
	if item_list.item_count > 0:
		item_list.select(0)
		item_list.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		scene_context.scene_stack.pop(_last_result)
		get_viewport().set_input_as_handled()


func _buy_at(index: int) -> void:
	if index < 0 or index >= _shop.entries.size():
		return
	_last_result = ShopTransaction.buy(scene_context.game_run, _shop.entries[index])
	var item := _shop.entries[index].item
	match _last_result.outcome:
		ShopResult.Outcome.PURCHASED:
			hint_label.text = "买下了%s" % item.display_name
		ShopResult.Outcome.INSUFFICIENT_FUNDS:
			hint_label.text = "钱不够"
		ShopResult.Outcome.INVENTORY_FULL:
			hint_label.text = "背包放不下"
		_:
			hint_label.text = "交易取消"
	_refresh(false)


func _refresh(reset_hint: bool = true) -> void:
	money_label.text = "现有 %d 文" % scene_context.game_run.economy.money
	item_list.clear()
	for entry: ShopEntry in _shop.entries:
		item_list.add_item("%s  %d 文\n%s" % [
			entry.item.display_name,
			entry.buy_price(),
			entry.item.description,
		])
	if reset_hint:
		hint_label.text = "Enter 购买 · Esc 离开"
