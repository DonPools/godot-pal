class_name BattleActionBuilder
extends RefCounted

const BASIC_ATTACK_ID := &"basic_attack"
const DODGE_ID := &"dodge"
const CHARGE_ID := &"charge"
const BASIC_CHAIN_WAVE_ID := &"basic_chain_wave"


static func build(
	intent: BattleActionIntent,
	source: BattleActorState,
	instance_id: int
) -> BattleActionState:
	if intent == null or source == null:
		return null
	var action := BattleActionState.new()
	action.instance_id = instance_id
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
			action.projectile_returns = (
				source.build.returning_projectile_skill_id == intent.skill.id
			)
			action.projectile_pierces = action.projectile_returns
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
		BattleActionIntent.Kind.CHARGE:
			action.action_id = CHARGE_ID
			action.windup_seconds = source.charge_windup_seconds
			action.active_seconds = source.charge_active_seconds
			action.recovery_seconds = source.charge_recovery_seconds
			action.base_damage = source.charge_damage
		_:
			return null
	action.remaining_seconds = action.windup_seconds
	return action


static func basic_chain_wave(
	source: BattleActorState,
	instance_id: int,
	fixed_step_seconds: float
) -> BattleActionState:
	var action := BattleActionState.new()
	action.instance_id = instance_id
	action.intent = BattleActionIntent.basic_attack(source.id)
	action.action_id = BASIC_CHAIN_WAVE_ID
	action.phase = BattleActionState.Phase.ACTIVE
	action.remaining_seconds = fixed_step_seconds
	action.active_seconds = fixed_step_seconds
	action.base_damage = source.build.basic_chain_wave_damage
	action.projectile_pierces = true
	return action


static func action_id(intent: BattleActionIntent) -> StringName:
	if intent == null:
		return &""
	match intent.kind:
		BattleActionIntent.Kind.BASIC_ATTACK:
			return BASIC_ATTACK_ID
		BattleActionIntent.Kind.SKILL:
			return intent.skill.id if intent.skill != null else &""
		BattleActionIntent.Kind.ITEM:
			return intent.item.id if intent.item != null else &""
		BattleActionIntent.Kind.DODGE:
			return DODGE_ID
		BattleActionIntent.Kind.CHARGE:
			return CHARGE_ID
	return &""
