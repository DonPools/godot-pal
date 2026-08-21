class_name BattleSession
extends RefCounted

const FIXED_STEP_SECONDS := 1.0 / 60.0
const MAX_ADVANCE_SECONDS := 0.25
const BASIC_ATTACK_ID := BattleActionBuilder.BASIC_ATTACK_ID
const DODGE_ID := BattleActionBuilder.DODGE_ID
const CHARGE_ID := BattleActionBuilder.CHARGE_ID

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
var _used_pillar_ids: Dictionary[StringName, bool] = {}


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
		session._working_inventory.restore(game_run.inventory.to_dictionary(), database)
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
	session.player.max_hp = CultivationRules.max_hp(actor_definition, leader, database)
	session.player.mp = leader.mp
	session.player.max_mp = CultivationRules.max_mp(actor_definition, leader, database)
	session.player.attack = CultivationRules.attack(actor_definition, leader, database)
	session.player.basic_attack_resource_gain = actor_definition.basic_attack_resource_gain
	session.player.build = BattleBuildSnapshot.create(leader, database)
	session.player.allowed_skill_ids = leader.battle_skill_ids.duplicate()
	session.player.battle_item_id = leader.battle_item_id
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
		actor.charge_damage = entry.enemy.charge_damage
		actor.charge_windup_seconds = entry.enemy.charge_windup_seconds
		actor.charge_active_seconds = entry.enemy.charge_active_seconds
		actor.charge_recovery_seconds = entry.enemy.charge_recovery_seconds
		actor.charge_speed = entry.enemy.charge_speed
		actor.charge_cooldown_seconds = entry.enemy.charge_cooldown_seconds
		actor.charge_stagger_seconds = entry.enemy.charge_stagger_seconds
		actor.charge_staggers_on_pillar = entry.enemy.charge_staggers_on_pillar
		session.enemies.append(actor)
		session._actors[actor.id] = actor
	return session


func actor(actor_id: StringName) -> BattleActorState:
	return _actors.get(actor_id)


func battle_item_quantity() -> int:
	if player == null or player.battle_item_id.is_empty():
		return 0
	return _working_inventory.quantity(player.battle_item_id)


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
	if not source.can_act():
		return _reject(intent, BattleActionRequestResult.Rejection.ACTOR_BUSY)
	if intent.kind == BattleActionIntent.Kind.SKILL:
		if (
			intent.skill == null
			or _database == null
			or _database.skill(intent.skill.id) != intent.skill
		):
			return _reject(intent, BattleActionRequestResult.Rejection.ACTION_INVALID)
		if not intent.skill.can_be_used_in_battle():
			return _reject(intent, BattleActionRequestResult.Rejection.ACTION_INVALID)
		if intent.skill.id not in source.allowed_skill_ids:
			return _reject(intent, BattleActionRequestResult.Rejection.SKILL_UNAVAILABLE)
	elif intent.kind == BattleActionIntent.Kind.ITEM:
		if (
			intent.item == null
			or _database == null
			or _database.item(intent.item.id) != intent.item
		):
			return _reject(intent, BattleActionRequestResult.Rejection.ACTION_INVALID)
		if not intent.item.can_be_used_in_battle():
			return _reject(intent, BattleActionRequestResult.Rejection.ACTION_INVALID)
		if intent.item.id != source.battle_item_id:
			return _reject(intent, BattleActionRequestResult.Rejection.ITEM_UNAVAILABLE)
	var action := BattleActionBuilder.build(intent, source, _next_action_instance_id)
	_next_action_instance_id += 1
	if action == null:
		return _reject(intent, BattleActionRequestResult.Rejection.ACTION_INVALID)
	if source.cooldown_remaining(action.action_id) > 0.0:
		return _reject(intent, BattleActionRequestResult.Rejection.COOLDOWN, action.action_id)
	var cooldown_started := 0.0
	if intent.kind == BattleActionIntent.Kind.SKILL:
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
		if _working_inventory.quantity(intent.item.id) <= 0:
			return _reject(intent, BattleActionRequestResult.Rejection.ITEM_UNAVAILABLE)
		var removal := _working_inventory.remove_item(intent.item, 1)
		if not removal.succeeded():
			return _reject(intent, BattleActionRequestResult.Rejection.ITEM_UNAVAILABLE)
	elif intent.kind == BattleActionIntent.Kind.DODGE:
		source.start_cooldown(action.action_id, 0.65)
		cooldown_started = 0.65
	elif intent.kind == BattleActionIntent.Kind.CHARGE:
		if source.charge_damage <= 0:
			return _reject(intent, BattleActionRequestResult.Rejection.ACTION_INVALID)
		source.start_cooldown(action.action_id, source.charge_cooldown_seconds)
		cooldown_started = source.charge_cooldown_seconds
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
	if is_delayed_projectile and not action.projectile_pierces:
		expire_projectile_action(action_instance_id)
	_check_outcome()
	return drain_events()


func expire_projectile_action(action_instance_id: int) -> void:
	_projectile_actions.erase(action_instance_id)
	_projectile_actor_ids.erase(action_instance_id)


func projectile_returns(action_instance_id: int) -> bool:
	var action := _projectile_actions.get(action_instance_id) as BattleActionState
	return action != null and action.projectile_returns


func projectile_pierces(action_instance_id: int) -> bool:
	var action := _projectile_actions.get(action_instance_id) as BattleActionState
	return action != null and action.projectile_pierces


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


func resolve_pillar_contact(
	actor_id: StringName,
	action_instance_id: int,
	pillar_id: StringName
) -> Array[BattleEvent]:
	if finished or pillar_id.is_empty() or _used_pillar_ids.has(pillar_id):
		return drain_events()
	var source := actor(actor_id)
	var action := source.current_action if source != null else null
	if (
		source == null
		or not source.charge_staggers_on_pillar
		or action == null
		or action.action_id != CHARGE_ID
		or action.instance_id != action_instance_id
		or action.phase != BattleActionState.Phase.ACTIVE
	):
		return drain_events()
	_used_pillar_ids[pillar_id] = true
	var consumed := BattleEvent.action_event(
		BattleEvent.Kind.PILLAR_CONSUMED,
		source.id,
		action
	)
	consumed.target_id = pillar_id
	_pending_events.append(consumed)
	source.current_action = null
	source.stagger_remaining_seconds = source.charge_stagger_seconds
	_pending_events.append(BattleEvent.duration_event(
		BattleEvent.Kind.STAGGER_STARTED,
		source.id,
		action,
		source.stagger_remaining_seconds
	))
	return drain_events()


func is_pillar_used(pillar_id: StringName) -> bool:
	return _used_pillar_ids.has(pillar_id)


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
	_game_run.inventory.restore(_working_inventory.to_dictionary(), _database)
	_game_run.randomness.restore(randomness.to_dictionary())
	result.state_changes[player.id] = {
		"hp": player.hp,
		"mp": player.mp,
	}
	if outcome == BattleResult.Outcome.VICTORY and encounter != null:
		BattleRewardCommitter.commit_victory(
			result,
			encounter,
			_defeated_enemy_ids,
			_game_run,
			_database
		)
	result.committed = true
	_committed_result = result
	return result


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
			result.action_id = BattleActionBuilder.action_id(intent)
		_pending_events.append(BattleEvent.rejection_event(
			intent.actor_id,
			result.action_id,
			reason
		))
	return result


func _advance_fixed_step(delta: float) -> void:
	elapsed_seconds += delta
	for battle_actor: BattleActorState in _actors.values():
		battle_actor.advance_cooldowns(delta)
		_advance_stagger(battle_actor, delta)
		_advance_statuses(battle_actor, delta)
		_advance_action(battle_actor, delta)
	_check_outcome()


func _advance_stagger(actor_state: BattleActorState, delta: float) -> void:
	if actor_state.stagger_remaining_seconds <= 0.0:
		return
	actor_state.stagger_remaining_seconds = maxf(
		actor_state.stagger_remaining_seconds - delta,
		0.0
	)
	if actor_state.stagger_remaining_seconds <= 0.0:
		var event := BattleEvent.new()
		event.kind = BattleEvent.Kind.STAGGER_ENDED
		event.actor_id = actor_state.id
		_pending_events.append(event)


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
		BattleActionIntent.Kind.BASIC_ATTACK, BattleActionIntent.Kind.CHARGE:
			var damage := target.take_damage(action.base_damage)
			_pending_events.append(BattleEvent.damage_event(
				source.id,
				target.id,
				action,
				damage
			))
			if action.applied_status != null and target.is_alive():
				_append_status_applied(target, action.applied_status)
			if action.action_id == BASIC_ATTACK_ID:
				_apply_basic_attack_build(source, action)
		BattleActionIntent.Kind.SKILL:
			_apply_effects(source, target, action, action.intent.skill.effects)
			_apply_skill_hit_build(source, action)
		BattleActionIntent.Kind.ITEM:
			_apply_effects(source, target, action, action.intent.item.effects)
	if not target.is_alive():
		_append_death(target)


func _apply_basic_attack_build(
	source: BattleActorState,
	action: BattleActionState
) -> void:
	if not action.resource_generated and source.basic_attack_resource_gain > 0:
		action.resource_generated = true
		_append_resource_restore(source, action, source.basic_attack_resource_gain)
	if source.build.basic_chain_length < 2 or source.build.basic_chain_wave_damage <= 0:
		return
	source.basic_chain_hits += 1
	if source.basic_chain_hits < source.build.basic_chain_length:
		return
	source.basic_chain_hits = 0
	_request_basic_chain_wave(source)


func _request_basic_chain_wave(source: BattleActorState) -> void:
	var wave := BattleActionBuilder.basic_chain_wave(
		source,
		_next_action_instance_id,
		FIXED_STEP_SECONDS
	)
	_next_action_instance_id += 1
	_projectile_actions[wave.instance_id] = wave
	_projectile_actor_ids[wave.instance_id] = source.id
	_pending_events.append(BattleEvent.action_event(
		BattleEvent.Kind.PROJECTILE_REQUESTED,
		source.id,
		wave
	))


func _apply_skill_hit_build(
	source: BattleActorState,
	action: BattleActionState
) -> void:
	if source.build.skill_hit_resource_refund > 0:
		_append_resource_restore(
			source,
			action,
			source.build.skill_hit_resource_refund
		)
	if source.build.skill_hit_cooldown_reduction > 0.0:
		source.reduce_cooldowns(source.build.skill_hit_cooldown_reduction)
		_pending_events.append(BattleEvent.duration_event(
			BattleEvent.Kind.COOLDOWN_REDUCED,
			source.id,
			action,
			source.build.skill_hit_cooldown_reduction
		))
	if (
		not action.build_bonus_applied
		and source.build.area_refund_skill_id == action.action_id
		and source.build.area_refund_target_count > 0
		and action.hit_targets.size() >= source.build.area_refund_target_count
	):
		action.build_bonus_applied = true
		_append_resource_restore(
			source,
			action,
			source.build.area_refund_amount
		)


func _append_resource_restore(
	source: BattleActorState,
	action: BattleActionState,
	amount: int
) -> void:
	var restored := source.restore_mp(amount)
	if restored <= 0:
		return
	var event := BattleEvent.action_event(
		BattleEvent.Kind.MP_RESTORED,
		source.id,
		action
	)
	event.target_id = source.id
	event.amount = restored
	_pending_events.append(event)


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
