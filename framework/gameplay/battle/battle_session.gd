class_name BattleSession
extends RefCounted

const FIXED_STEP_SECONDS := 1.0 / 60.0
const MAX_ADVANCE_SECONDS := 0.25
const BASIC_ATTACK_ID := &"basic_attack"
const DODGE_ID := &"dodge"

var encounter: BattleEncounter
var player: BattleActorState
var enemies: Array[BattleActorState] = []
var randomness := RandomState.new()
var enemy: BattleActorState:
	get:
		return enemies[0] if not enemies.is_empty() else null
var elapsed_seconds: float = 0.0
var finished: bool = false
var outcome: BattleResult.Outcome = BattleResult.Outcome.CANCELLED

var _game_run: GameRun
var _database: ContentDatabase
var _working_inventory := InventoryState.new()
var _actors: Dictionary[StringName, BattleActorState] = {}
var _pending_events: Array[BattleEvent] = []
var _accumulator: float = 0.0
var _next_action_instance_id: int = 1
var _defeated_enemy_ids: Array[StringName] = []
var _committed_result: BattleResult
var _projectile_actions: Dictionary[int, BattleActionState] = {}
var _projectile_actor_ids: Dictionary[int, StringName] = {}


static func create(
	definition: BattleEncounter,
	game_run: GameRun,
	database: ContentDatabase
) -> BattleSession:
	var session := BattleSession.new()
	session.encounter = definition
	session._game_run = game_run
	session._database = database
	if game_run != null:
		session._working_inventory.restore(game_run.inventory.to_dictionary())
		session.randomness.restore(game_run.randomness.to_dictionary())
	if definition == null or game_run == null or database == null:
		return session
	var leader := game_run.party.leader()
	var actor_definition := (
		database.actor(leader.definition_id)
		if leader != null
		else null
	)
	if leader == null or actor_definition == null:
		return session
	session.player = BattleActorState.new()
	session.player.id = leader.definition_id
	session.player.definition_id = leader.definition_id
	session.player.display_name = actor_definition.display_name
	session.player.hp = leader.hp
	session.player.max_hp = actor_definition.base_max_hp
	session.player.mp = leader.mp
	session.player.max_mp = actor_definition.base_max_mp
	session.player.attack = 12 + leader.level * 2
	session.player.move_speed = 4.5
	session._actors[session.player.id] = session.player
	for entry: EncounterEnemy in definition.enemies:
		if entry == null or entry.enemy == null or entry.instance_id.is_empty():
			continue
		var actor := BattleActorState.new()
		actor.id = entry.instance_id
		actor.definition_id = entry.enemy.id
		actor.display_name = entry.enemy.display_name
		actor.hp = entry.enemy.max_hp
		actor.max_hp = entry.enemy.max_hp
		actor.mp = 0
		actor.max_mp = 0
		actor.attack = entry.enemy.attack
		actor.move_speed = entry.enemy.move_speed
		actor.attack_windup_seconds = entry.enemy.attack_windup_seconds
		actor.attack_active_seconds = entry.enemy.attack_active_seconds
		actor.attack_recovery_seconds = entry.enemy.attack_recovery_seconds
		if entry.enemy.strategy != null:
			var enemy_action := entry.enemy.strategy.choose_action(actor, session.player)
			actor.attack = enemy_action.damage
			actor.attack_status = enemy_action.applied_status
		session.enemies.append(actor)
		session._actors[actor.id] = actor
	return session


func actor(actor_id: StringName) -> BattleActorState:
	return _actors.get(actor_id)


func request_action(intent: BattleActionIntent) -> BattleActionRequestResult:
	if finished:
		return _reject(intent, BattleActionRequestResult.Rejection.SESSION_FINISHED)
	if intent == null:
		return _reject(intent, BattleActionRequestResult.Rejection.ACTION_INVALID)
	var source := actor(intent.actor_id)
	if source == null:
		return _reject(intent, BattleActionRequestResult.Rejection.ACTOR_NOT_FOUND)
	if not source.is_alive():
		return _reject(intent, BattleActionRequestResult.Rejection.ACTOR_DEAD)
	if source.current_action != null:
		return _reject(intent, BattleActionRequestResult.Rejection.ACTOR_BUSY)
	var action := _build_action(intent, source)
	if action == null:
		return _reject(intent, BattleActionRequestResult.Rejection.ACTION_INVALID)
	if source.cooldown_remaining(action.action_id) > 0.0:
		return _reject(intent, BattleActionRequestResult.Rejection.COOLDOWN, action.action_id)
	var cooldown_started := 0.0
	if intent.kind == BattleActionIntent.Kind.SKILL:
		if intent.skill == null or not intent.skill.usable_in_battle:
			return _reject(intent, BattleActionRequestResult.Rejection.ACTION_INVALID)
		if source.mp < intent.skill.mp_cost:
			return _reject(
				intent,
				BattleActionRequestResult.Rejection.INSUFFICIENT_RESOURCE,
				action.action_id
			)
		source.mp -= intent.skill.mp_cost
		source.start_cooldown(action.action_id, intent.skill.cooldown_seconds)
		cooldown_started = intent.skill.cooldown_seconds
	elif intent.kind == BattleActionIntent.Kind.ITEM:
		if (
			intent.item == null
			or not intent.item.usable_in_battle
			or _working_inventory.quantity(intent.item.id) <= 0
		):
			return _reject(intent, BattleActionRequestResult.Rejection.ITEM_UNAVAILABLE)
		var removal := _working_inventory.remove_item(intent.item, 1)
		if not removal.succeeded():
			return _reject(intent, BattleActionRequestResult.Rejection.ITEM_UNAVAILABLE)
	elif intent.kind == BattleActionIntent.Kind.DODGE:
		source.start_cooldown(action.action_id, 0.65)
		cooldown_started = 0.65
	source.current_action = action
	_pending_events.append(BattleEvent.action_event(
		BattleEvent.Kind.ACTION_STARTED,
		source.id,
		action
	))
	if intent.kind == BattleActionIntent.Kind.DODGE:
		_pending_events.append(BattleEvent.duration_event(
			BattleEvent.Kind.DODGE_STARTED,
			source.id,
			action,
			action.active_seconds
		))
	if cooldown_started > 0.0:
		_pending_events.append(BattleEvent.duration_event(
			BattleEvent.Kind.COOLDOWN_STARTED,
			source.id,
			action,
			cooldown_started
		))
	var result := BattleActionRequestResult.new()
	result.action_instance_id = action.instance_id
	result.action_id = action.action_id
	return result


func advance(delta: float) -> Array[BattleEvent]:
	if finished or delta <= 0.0:
		return drain_events()
	_accumulator += minf(delta, MAX_ADVANCE_SECONDS)
	while _accumulator >= FIXED_STEP_SECONDS and not finished:
		_advance_fixed_step(FIXED_STEP_SECONDS)
		_accumulator -= FIXED_STEP_SECONDS
	return drain_events()


func resolve_hit(
	actor_id: StringName,
	action_instance_id: int,
	target_id: StringName
) -> Array[BattleEvent]:
	if finished:
		return drain_events()
	var source := actor(actor_id)
	var target := actor(target_id)
	var action := source.current_action if source != null else null
	var is_delayed_projectile := false
	if (
		action == null
		or action.instance_id != action_instance_id
		or action.phase != BattleActionState.Phase.ACTIVE
	):
		action = _projectile_actions.get(action_instance_id) as BattleActionState
		is_delayed_projectile = action != null
	if (
		source == null
		or target == null
		or not target.is_alive()
		or action == null
		or action.instance_id != action_instance_id
		or (
			is_delayed_projectile
			and _projectile_actor_ids.get(action_instance_id, &"") != actor_id
		)
		or action.has_hit(target_id)
	):
		return drain_events()
	action.record_hit(target_id)
	if _is_dodge_invulnerable(target):
		var dodged := BattleEvent.action_event(
			BattleEvent.Kind.DODGED,
			target.id,
			target.current_action
		)
		dodged.target_id = source.id
		_pending_events.append(dodged)
		if is_delayed_projectile:
			expire_projectile_action(action_instance_id)
		return drain_events()
	_apply_action_effects(source, target, action)
	if is_delayed_projectile:
		expire_projectile_action(action_instance_id)
	_check_outcome()
	return drain_events()


func expire_projectile_action(action_instance_id: int) -> void:
	_projectile_actions.erase(action_instance_id)
	_projectile_actor_ids.erase(action_instance_id)


func apply_status(target_id: StringName, definition: StatusDefinition) -> Array[BattleEvent]:
	var target := actor(target_id)
	if finished or target == null or not target.is_alive() or definition == null:
		return drain_events()
	var newly_applied := target.apply_status(definition)
	var event := BattleEvent.new()
	event.kind = BattleEvent.Kind.STATUS_APPLIED
	event.actor_id = target.id
	event.action_id = definition.id
	event.amount = 1 if newly_applied else 0
	_pending_events.append(event)
	return drain_events()


func finish_escape() -> BattleResult:
	if finished:
		return _result_snapshot()
	if encounter == null or not encounter.allows_escape:
		_pending_events.append(BattleEvent.rejection_event(
			player.id if player != null else &"",
			&"escape",
			BattleActionRequestResult.Rejection.ACTION_INVALID
		))
		return _result_snapshot()
	_finish(BattleResult.Outcome.ESCAPED)
	return _result_snapshot()


func finish_cancelled() -> BattleResult:
	if not finished:
		_finish(BattleResult.Outcome.CANCELLED)
	return _result_snapshot()


func drain_events() -> Array[BattleEvent]:
	var drained: Array[BattleEvent] = _pending_events.duplicate()
	_pending_events.clear()
	return drained


func commit_result() -> BattleResult:
	if _committed_result != null:
		return _committed_result
	var result := _result_snapshot()
	if not finished or _game_run == null or player == null:
		return result
	var leader := _game_run.party.leader()
	if leader != null:
		leader.hp = player.hp
		leader.mp = player.mp
	_game_run.inventory.restore(_working_inventory.to_dictionary())
	_game_run.randomness.restore(randomness.to_dictionary())
	result.state_changes[player.id] = {
		"hp": player.hp,
		"mp": player.mp,
	}
	if outcome == BattleResult.Outcome.VICTORY and encounter != null:
		_commit_victory_rewards(result)
	result.committed = true
	_committed_result = result
	return result


func _build_action(
	intent: BattleActionIntent,
	source: BattleActorState
) -> BattleActionState:
	var action := BattleActionState.new()
	action.instance_id = _next_action_instance_id
	_next_action_instance_id += 1
	action.intent = intent
	match intent.kind:
		BattleActionIntent.Kind.BASIC_ATTACK:
			action.action_id = BASIC_ATTACK_ID
			action.windup_seconds = source.attack_windup_seconds
			action.active_seconds = source.attack_active_seconds
			action.recovery_seconds = source.attack_recovery_seconds
			action.base_damage = source.attack
			action.applied_status = source.attack_status
		BattleActionIntent.Kind.SKILL:
			if intent.skill == null:
				return null
			action.action_id = intent.skill.id
			action.windup_seconds = intent.skill.cast_seconds
			action.active_seconds = intent.skill.active_seconds
			action.recovery_seconds = intent.skill.recovery_seconds
		BattleActionIntent.Kind.ITEM:
			if intent.item == null:
				return null
			action.action_id = intent.item.id
			action.windup_seconds = 0.1
			action.active_seconds = 0.05
			action.recovery_seconds = 0.2
		BattleActionIntent.Kind.DODGE:
			action.action_id = DODGE_ID
			action.windup_seconds = 0.0
			action.active_seconds = 0.22
			action.recovery_seconds = 0.43
		_:
			return null
	action.remaining_seconds = action.windup_seconds
	return action


func _reject(
	intent: BattleActionIntent,
	reason: BattleActionRequestResult.Rejection,
	action_id: StringName = &""
) -> BattleActionRequestResult:
	var result := BattleActionRequestResult.new()
	result.rejection = reason
	result.action_id = action_id
	if intent != null:
		if result.action_id.is_empty():
			result.action_id = _intent_action_id(intent)
		_pending_events.append(BattleEvent.rejection_event(
			intent.actor_id,
			result.action_id,
			reason
		))
	return result


func _intent_action_id(intent: BattleActionIntent) -> StringName:
	match intent.kind:
		BattleActionIntent.Kind.BASIC_ATTACK:
			return BASIC_ATTACK_ID
		BattleActionIntent.Kind.SKILL:
			return intent.skill.id if intent.skill != null else &""
		BattleActionIntent.Kind.ITEM:
			return intent.item.id if intent.item != null else &""
		BattleActionIntent.Kind.DODGE:
			return DODGE_ID
	return &""


func _advance_fixed_step(delta: float) -> void:
	elapsed_seconds += delta
	for battle_actor: BattleActorState in _actors.values():
		battle_actor.advance_cooldowns(delta)
		_advance_statuses(battle_actor, delta)
		_advance_action(battle_actor, delta)
	_check_outcome()


func _advance_action(battle_actor: BattleActorState, delta: float) -> void:
	var action := battle_actor.current_action
	if action == null:
		return
	action.remaining_seconds -= delta
	if action.remaining_seconds > 0.0:
		return
	match action.phase:
		BattleActionState.Phase.WINDUP:
			action.phase = BattleActionState.Phase.ACTIVE
			action.remaining_seconds = maxf(action.active_seconds, FIXED_STEP_SECONDS)
			_pending_events.append(BattleEvent.action_event(
				BattleEvent.Kind.ACTION_ACTIVE,
				battle_actor.id,
				action
			))
			if _action_uses_projectile(battle_actor, action):
				_projectile_actions[action.instance_id] = action
				_projectile_actor_ids[action.instance_id] = battle_actor.id
				_pending_events.append(BattleEvent.action_event(
					BattleEvent.Kind.PROJECTILE_REQUESTED,
					battle_actor.id,
					action
				))
		BattleActionState.Phase.ACTIVE:
			action.phase = BattleActionState.Phase.RECOVERY
			action.remaining_seconds = maxf(action.recovery_seconds, FIXED_STEP_SECONDS)
		BattleActionState.Phase.RECOVERY:
			_pending_events.append(BattleEvent.action_event(
				BattleEvent.Kind.ACTION_FINISHED,
				battle_actor.id,
				action
			))
			battle_actor.current_action = null


func _advance_statuses(target: BattleActorState, delta: float) -> void:
	for status_id: StringName in target.statuses.keys():
		var state := target.statuses[status_id]
		var definition := _database.status(status_id) if _database != null else null
		if definition == null:
			target.statuses.erase(status_id)
			continue
		state.remaining_seconds = maxf(state.remaining_seconds - delta, 0.0)
		state.tick_remaining_seconds -= delta
		if state.tick_remaining_seconds <= 0.0 and target.is_alive():
			state.tick_remaining_seconds += definition.tick_interval_seconds
			var damage := target.take_damage(definition.periodic_damage)
			var event := BattleEvent.new()
			event.kind = BattleEvent.Kind.STATUS_TICK
			event.actor_id = target.id
			event.action_id = status_id
			event.amount = damage
			_pending_events.append(event)
			if not target.is_alive():
				_append_death(target)
		if state.remaining_seconds <= 0.0:
			target.statuses.erase(status_id)


func _apply_action_effects(
	source: BattleActorState,
	target: BattleActorState,
	action: BattleActionState
) -> void:
	match action.intent.kind:
		BattleActionIntent.Kind.BASIC_ATTACK:
			var damage := target.take_damage(action.base_damage)
			_pending_events.append(BattleEvent.damage_event(
				source.id,
				target.id,
				action,
				damage
			))
			if action.applied_status != null and target.is_alive():
				_append_status_applied(target, action.applied_status)
		BattleActionIntent.Kind.SKILL:
			_apply_effects(source, target, action, action.intent.skill.effects)
		BattleActionIntent.Kind.ITEM:
			_apply_effects(source, target, action, action.intent.item.effects)
	if not target.is_alive():
		_append_death(target)


func _append_status_applied(target: BattleActorState, definition: StatusDefinition) -> void:
	var newly_applied := target.apply_status(definition)
	var event := BattleEvent.new()
	event.kind = BattleEvent.Kind.STATUS_APPLIED
	event.actor_id = target.id
	event.action_id = definition.id
	event.amount = 1 if newly_applied else 0
	_pending_events.append(event)


func _action_uses_projectile(
	source: BattleActorState,
	action: BattleActionState
) -> bool:
	if (
		action.intent.kind == BattleActionIntent.Kind.SKILL
		and action.intent.skill != null
		and action.intent.skill.target_rule == SkillDefinition.TargetRule.DIRECTION
	):
		return true
	if action.intent.kind != BattleActionIntent.Kind.BASIC_ATTACK or _database == null:
		return false
	var enemy_definition := _database.enemy(source.definition_id)
	return (
		enemy_definition != null
		and enemy_definition.combat_style == EnemyDefinition.CombatStyle.RANGED
	)


func _apply_effects(
	source: BattleActorState,
	target: BattleActorState,
	action: BattleActionState,
	effects: Array[GameEffect]
) -> void:
	for effect: GameEffect in effects:
		if effect == null:
			continue
		var result := effect.apply(EffectContext.create_for_battle(source.id, target))
		var event_kind := BattleEvent.Kind.HEAL
		if effect is DamageEffect:
			event_kind = BattleEvent.Kind.DAMAGE
		elif effect is RestoreMpEffect:
			event_kind = BattleEvent.Kind.MP_RESTORED
		var event := BattleEvent.action_event(
			event_kind,
			source.id,
			action
		)
		event.target_id = target.id
		event.amount = result.changed_amount
		_pending_events.append(event)


func _is_dodge_invulnerable(target: BattleActorState) -> bool:
	return (
		target.current_action != null
		and target.current_action.action_id == DODGE_ID
		and target.current_action.phase == BattleActionState.Phase.ACTIVE
	)


func _append_death(target: BattleActorState) -> void:
	var event := BattleEvent.new()
	event.kind = BattleEvent.Kind.DEATH
	event.actor_id = target.id
	_pending_events.append(event)
	if target != player and target.id not in _defeated_enemy_ids:
		_defeated_enemy_ids.append(target.id)


func _check_outcome() -> void:
	if finished or player == null:
		return
	if not player.is_alive():
		_finish(BattleResult.Outcome.DEFEAT)
		return
	if not enemies.is_empty():
		for opponent: BattleActorState in enemies:
			if opponent.is_alive():
				return
		_finish(BattleResult.Outcome.VICTORY)


func _finish(value: BattleResult.Outcome) -> void:
	if finished:
		return
	finished = true
	outcome = value
	_pending_events.append(BattleEvent.outcome_event(value))


func _result_snapshot() -> BattleResult:
	if _committed_result != null:
		return _committed_result
	var result := BattleResult.new()
	result.outcome = outcome
	result.encounter_id = encounter.id if encounter != null else &""
	result.duration_msec = roundi(elapsed_seconds * 1000.0)
	result.defeated_enemy_ids.assign(_defeated_enemy_ids)
	return result


func _commit_victory_rewards(result: BattleResult) -> void:
	var item_order: Array[StringName] = []
	var item_definitions: Dictionary[StringName, ItemDefinition] = {}
	var requested_items: Dictionary[StringName, int] = {}
	for entry: EncounterEnemy in encounter.enemies:
		if entry == null or entry.enemy == null or entry.instance_id not in _defeated_enemy_ids:
			continue
		result.experience_reward += entry.enemy.experience_reward
		result.money_reward += entry.enemy.money_reward
		if entry.enemy.drop_item != null and entry.enemy.drop_quantity > 0:
			var item_id := entry.enemy.drop_item.id
			if not requested_items.has(item_id):
				item_order.append(item_id)
				item_definitions[item_id] = entry.enemy.drop_item
			requested_items[item_id] = (
				int(requested_items.get(item_id, 0)) + entry.enemy.drop_quantity
			)
	var leader := _game_run.party.leader()
	if leader != null and result.experience_reward > 0:
		leader.add_experience(result.experience_reward)
	if result.money_reward > 0:
		_game_run.economy.add_money(result.money_reward)
	_commit_item_rewards(result, item_order, item_definitions, requested_items)
	if not result.dropped_items.is_empty():
		result.dropped_item_id = result.dropped_items.keys()[0]
		result.dropped_quantity = result.dropped_items[result.dropped_item_id]


func _commit_item_rewards(
	result: BattleResult,
	item_order: Array[StringName],
	item_definitions: Dictionary[StringName, ItemDefinition],
	requested_items: Dictionary[StringName, int]
) -> void:
	if item_order.is_empty():
		return
	var trial := InventoryState.new()
	if not trial.restore(_game_run.inventory.to_dictionary()):
		return
	for item_id: StringName in item_order:
		var requested := int(requested_items[item_id])
		var reward := trial.add_item(
			item_definitions[item_id],
			requested,
			encounter.reward_policy
		)
		if reward.changed_quantity > 0:
			result.dropped_items[item_id] = reward.changed_quantity
		if reward.rejected_quantity > 0:
			result.rejected_dropped_items[item_id] = reward.rejected_quantity
		if (
			encounter.reward_policy == RewardPolicy.Value.ALL_OR_NOTHING
			and not reward.succeeded()
		):
			result.dropped_items.clear()
			result.rejected_dropped_items.clear()
			for rejected_id: StringName in item_order:
				result.rejected_dropped_items[rejected_id] = int(requested_items[rejected_id])
			return
	_game_run.inventory.restore(trial.to_dictionary())
