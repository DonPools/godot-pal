class_name BattleGameScene
extends GameScene

@onready var title_label: Label = $UiLayer/Panel/Title
@onready var player_label: Label = $UiLayer/Panel/Player
@onready var enemy_label: Label = $UiLayer/Panel/Enemy
@onready var log_label: Label = $UiLayer/Panel/Log
@onready var command_list: ItemList = $UiLayer/Panel/Commands

var session: BattleSession


func enter(context: GameSceneContext, arguments: Variant) -> void:
	super.enter(context, arguments)
	var encounter := arguments as BattleEncounter
	if encounter == null or encounter.enemies.is_empty():
		push_error("BattleGameScene requires a valid BattleEncounter")
		context.scene_stack.pop(BattleResult.new())
		return
	session = BattleSession.create(encounter, context.game_run, context.content_database)
	title_label.text = encounter.display_name
	for command_name: String in ["攻击", "技能", "物品", "防御", "逃跑"]:
		command_list.add_item(command_name)
	command_list.item_activated.connect(_execute_command)
	command_list.select(0)
	command_list.grab_focus()
	_refresh()


func _execute_command(index: int) -> void:
	if session == null or session.finished or index < 0 or index > 4:
		return
	var events := session.execute(index as BattleSession.Command)
	var messages := PackedStringArray()
	for event: BattleEvent in events:
		messages.append(event.message)
	log_label.text = "\n".join(messages)
	_refresh()
	if session.finished:
		command_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		await get_tree().create_timer(0.05).timeout
		scene_context.scene_stack.pop(session.commit_result())


func _refresh() -> void:
	player_label.text = "%s  HP %d/%d  MP %d/%d" % [
		session.player.display_name,
		session.player.hp,
		session.player.max_hp,
		session.player.mp,
		session.player.max_mp,
	]
	enemy_label.text = "%s  HP %d/%d" % [
		session.enemy.display_name,
		session.enemy.hp,
		session.enemy.max_hp,
	]
