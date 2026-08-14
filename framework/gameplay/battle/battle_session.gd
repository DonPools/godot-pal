class_name BattleSession
extends RefCounted

enum Command {
	ATTACK,
	SKILL,
	ITEM,
	DEFEND,
	ESCAPE,
}

var encounter: BattleEncounter
var player: BattleActorState
var enemy: BattleActorState
var rounds: int = 0
var finished: bool = false
var outcome: BattleResult.Outcome = BattleResult.Outcome.CANCELLED
var events: Array[BattleEvent] = []

var _game_run: GameRun
var _database: ContentDatabase
var _working_inventory := InventoryState.new()
var _enemy_strategy: EnemyStrategy


static func create(
	definition: BattleEncounter,
	game_run: GameRun,
	database: ContentDatabase
) -> BattleSession:
	var session := BattleSession.new()
	session.encounter = definition
	session._game_run = game_run
	session._database = database
	session._working_inventory.restore(game_run.inventory.to_dictionary())
	var leader := game_run.party.leader()
	var actor_definition := database.actor(leader.definition_id)
	session.player = BattleActorState.new()
	session.player.id = leader.definition_id
	session.player.display_name = actor_definition.display_name
	session.player.hp = leader.hp
	session.player.max_hp = actor_definition.base_max_hp
	session.player.mp = leader.mp
	session.player.max_mp = actor_definition.base_max_mp
	session.player.attack = 12 + leader.level * 2
	var enemy_definition := definition.enemies[0].enemy
	session._enemy_strategy = enemy_definition.strategy
	session.enemy = BattleActorState.new()
	session.enemy.id = definition.enemies[0].instance_id
	session.enemy.display_name = enemy_definition.display_name
	session.enemy.hp = enemy_definition.max_hp
	session.enemy.max_hp = enemy_definition.max_hp
	session.enemy.attack = enemy_definition.attack
	return session


func execute(command: Command) -> Array[BattleEvent]:
	events.clear()
	if finished:
		return events
	rounds += 1
	player.defending = false
	_tick_player_statuses()
	if player.hp <= 0:
		_finish(BattleResult.Outcome.DEFEAT, "%s倒下了" % player.display_name)
		return events
	match command:
		Command.ATTACK:
			_damage_enemy(player.attack, "%s挥剑攻击" % player.display_name)
		Command.SKILL:
			_execute_skill()
		Command.ITEM:
			_execute_item()
		Command.DEFEND:
			player.defending = true
			events.append(BattleEvent.message_event("%s凝神防御" % player.display_name))
		Command.ESCAPE:
			if encounter.allows_escape:
				_finish(BattleResult.Outcome.ESCAPED, "成功脱离战斗")
				return events
			events.append(BattleEvent.message_event("无法逃跑"))
	if enemy.hp <= 0:
		_finish(BattleResult.Outcome.VICTORY, "%s被击败" % enemy.display_name)
		return events
	_enemy_turn()
	if player.hp <= 0:
		_finish(BattleResult.Outcome.DEFEAT, "%s倒下了" % player.display_name)
	return events


func commit_result() -> BattleResult:
	var result := BattleResult.new()
	result.outcome = outcome
	result.encounter_id = encounter.id
	result.rounds = rounds
	var leader := _game_run.party.leader()
	leader.hp = player.hp
	leader.mp = player.mp
	_game_run.inventory.restore(_working_inventory.to_dictionary())
	if outcome == BattleResult.Outcome.VICTORY:
		var enemy_definition := encounter.enemies[0].enemy
		result.money_reward = enemy_definition.money_reward
		_game_run.economy.add_money(result.money_reward)
		if enemy_definition.drop_item != null and enemy_definition.drop_quantity > 0:
			var reward := _game_run.inventory.add_item(
				enemy_definition.drop_item,
				enemy_definition.drop_quantity,
				RewardPolicy.Value.ALL_OR_NOTHING
			)
			if reward.succeeded():
				result.dropped_item_id = enemy_definition.drop_item.id
				result.dropped_quantity = reward.changed_quantity
	return result


func _execute_skill() -> void:
	var leader := _game_run.party.leader()
	if leader.skill_ids.is_empty():
		events.append(BattleEvent.message_event("没有可用技能"))
		return
	var skill := _database.skill(leader.skill_ids[0])
	if skill == null or player.mp < skill.mp_cost:
		events.append(BattleEvent.message_event("真气不足"))
		return
	player.mp -= skill.mp_cost
	var effect_damage := 0
	for effect: GameEffect in skill.effects:
		if effect is DamageEffect:
			effect_damage += (effect as DamageEffect).amount
	_damage_enemy(
		maxi(effect_damage, player.attack),
		"%s施展%s" % [player.display_name, skill.display_name]
	)


func _execute_item() -> void:
	for item_id: StringName in _working_inventory.item_ids():
		var item := _database.item(item_id)
		if item != null and item.usable_in_battle:
			var leader := ActorState.new()
			leader.definition_id = player.id
			leader.hp = player.hp
			leader.mp = player.mp
			var working_run := GameRun.new()
			working_run.party.add_member(leader)
			working_run.inventory = _working_inventory
			var actor_definition := _database.actor(player.id)
			var use_result := ItemUseTransaction.use_on_actor(
				working_run,
				item,
				leader,
				actor_definition
			)
			player.hp = leader.hp
			player.mp = leader.mp
			if use_result.used():
				events.append(BattleEvent.message_event("使用了%s" % item.display_name))
				return
		events.append(BattleEvent.message_event("没有可用物品"))


func _damage_enemy(amount: int, message: String) -> void:
	events.append(BattleEvent.message_event(message))
	var damage := enemy.take_damage(amount)
	var event := BattleEvent.new()
	event.kind = BattleEvent.Kind.DAMAGE
	event.actor_id = enemy.id
	event.amount = damage
	event.message = "%s受到 %d 点伤害" % [enemy.display_name, damage]
	events.append(event)


func _enemy_turn() -> void:
	var action := (
		_enemy_strategy.choose_action(enemy, player)
		if _enemy_strategy != null
		else EnemyAction.attack(enemy.attack)
	)
	var damage := player.take_damage(action.damage)
	var event := BattleEvent.new()
	event.kind = BattleEvent.Kind.DAMAGE
	event.actor_id = player.id
	event.amount = damage
	event.message = "%s反击，造成 %d 点伤害" % [enemy.display_name, damage]
	events.append(event)
	if player.is_alive() and action.applied_status != null:
		var newly_applied := player.apply_status(action.applied_status)
		var status_event := BattleEvent.new()
		status_event.kind = BattleEvent.Kind.STATUS
		status_event.actor_id = player.id
		status_event.message = (
			"%s陷入%s" % [player.display_name, action.applied_status.display_name]
			if newly_applied
			else "%s的%s持续" % [player.display_name, action.applied_status.display_name]
		)
		events.append(status_event)


func _tick_player_statuses() -> void:
	for status_id: StringName in player.statuses.keys():
		var definition := _database.status(status_id)
		if definition == null:
			player.statuses.erase(status_id)
			continue
		var damage := player.tick_status(definition)
		if damage > 0:
			var event := BattleEvent.new()
			event.kind = BattleEvent.Kind.STATUS
			event.actor_id = player.id
			event.amount = damage
			event.message = "%s受到%s影响，损失 %d 点体力" % [
				player.display_name, definition.display_name, damage,
			]
			events.append(event)


func _finish(result: BattleResult.Outcome, message: String) -> void:
	finished = true
	outcome = result
	var event := BattleEvent.message_event(message)
	event.kind = BattleEvent.Kind.OUTCOME
	events.append(event)
