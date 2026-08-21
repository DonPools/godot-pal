class_name BattleActionTestSuite
extends BattleTestSuiteBase


func run() -> PackedStringArray:
	_test_action_timeline_and_fixed_step()
	_test_skill_rejections_and_effects()
	_test_basic_attack_resource_generation()
	_test_equipment_build_modifiers()
	_test_foundation_build_modifiers()
	_test_charge_and_pillar_stagger()
	_test_dodge_invulnerability()
	_test_projectile_hit_after_action_recovery()
	_test_timed_status_ticks()
	return _failures


func _test_action_timeline_and_fixed_step() -> void:
	var first := _fixture(1)
	var second := _fixture(1)
	var first_session := first.session as BattleSession
	var second_session := second.session as BattleSession
	var first_request := first_session.request_action(
		BattleActionIntent.basic_attack(first_session.player.id)
	)
	var second_request := second_session.request_action(
		BattleActionIntent.basic_attack(second_session.player.id)
	)
	_expect(first_request.accepted() and second_request.accepted(), "basic attacks should be accepted")
	var started := first_session.drain_events()
	second_session.drain_events()
	_expect(
		started.size() == 1 and started[0].kind == BattleEvent.Kind.ACTION_STARTED,
		"an accepted action should emit ACTION_STARTED exactly once"
	)
	var busy := first_session.request_action(BattleActionIntent.dodge(first_session.player.id))
	_expect(
		busy.rejection == BattleActionRequestResult.Rejection.ACTOR_BUSY,
		"a second action should be rejected while the actor is busy"
	)
	first_session.drain_events()
	first_session.advance(0.25)
	for _step: int in range(15):
		second_session.advance(BattleSession.FIXED_STEP_SECONDS)
	_expect(
		is_equal_approx(first_session.elapsed_seconds, second_session.elapsed_seconds),
		"one batched advance and equivalent fixed advances should use the same rule time"
	)
	_expect(
		first_session.player.current_action.phase == second_session.player.current_action.phase
		and is_equal_approx(
			first_session.player.current_action.remaining_seconds,
			second_session.player.current_action.remaining_seconds
		),
		"fixed-step action state should not depend on presentation frame grouping"
	)
	var hit_fixture := _fixture(1)
	var hit_session := hit_fixture.session as BattleSession
	var hit_request := hit_session.request_action(
		BattleActionIntent.basic_attack(hit_session.player.id)
	)
	hit_session.drain_events()
	_advance_until_active(hit_session, hit_session.player)
	var target := hit_session.enemies[0]
	var hp_before := target.hp
	var hit_events := hit_session.resolve_hit(
		hit_session.player.id,
		hit_request.action_instance_id,
		target.id
	)
	_expect(
		_count_kind(hit_events, BattleEvent.Kind.DAMAGE) == 1
		and target.hp < hp_before,
		"an active basic attack should emit one damage event"
	)
	var hp_after := target.hp
	_expect(
		hit_session.resolve_hit(
			hit_session.player.id,
			hit_request.action_instance_id,
			target.id
		).is_empty()
		and target.hp == hp_after,
		"one action instance must not hit the same target twice"
	)


func _test_skill_rejections_and_effects() -> void:
	var fixture := _fixture(1)
	var session := fixture.session as BattleSession
	var skill := fixture.skill as SkillDefinition
	var starting_mp := session.player.mp
	var request := session.request_action(BattleActionIntent.use_skill(session.player.id, skill))
	_expect(request.accepted(), "a usable skill with enough MP should be accepted")
	_expect(session.player.mp == starting_mp - skill.mp_cost, "accepted skills should spend MP once")
	var request_events := session.drain_events()
	_expect(
		_contains_kind(request_events, BattleEvent.Kind.COOLDOWN_STARTED),
		"an accepted skill should emit a cooldown event"
	)
	var active_events: Array[BattleEvent] = []
	for _step: int in range(120):
		active_events.append_array(session.advance(BattleSession.FIXED_STEP_SECONDS))
		if (
			session.player.current_action != null
			and session.player.current_action.phase == BattleActionState.Phase.ACTIVE
		):
			break
	_expect(
		_contains_kind(active_events, BattleEvent.Kind.ACTION_ACTIVE)
		and _contains_kind(active_events, BattleEvent.Kind.PROJECTILE_REQUESTED),
		"a directional skill should request its projectile when it becomes active"
	)
	var target := session.enemies[0]
	var hp_before := target.hp
	session.resolve_hit(session.player.id, request.action_instance_id, target.id)
	_expect(target.hp == hp_before - 9, "skill effects should apply through the typed EffectContext")
	_advance_until_idle(session, session.player)
	var cooldown := session.request_action(BattleActionIntent.use_skill(session.player.id, skill))
	_expect(
		cooldown.rejection == BattleActionRequestResult.Rejection.COOLDOWN,
		"skills should reject requests while cooldown remains"
	)
	var expensive := skill.duplicate(true) as SkillDefinition
	expensive.id = &"skill.test.expensive"
	expensive.mp_cost = session.player.max_mp + 1
	var other := _fixture(1)
	var other_database := other.database as ContentDatabase
	var other_run := other.run as GameRun
	other_database.skills.append(expensive)
	other_run.party.leader().learned_skill_ids.append(expensive.id)
	other_run.party.leader().battle_skill_ids[0] = expensive.id
	other_database.build_index()
	var other_session := BattleSession.create(other.encounter, other_run, other_database)
	var insufficient := other_session.request_action(
		BattleActionIntent.use_skill(other_session.player.id, expensive)
	)
	_expect(
		insufficient.rejection == BattleActionRequestResult.Rejection.INSUFFICIENT_RESOURCE,
		"skills should reject requests without enough MP"
	)
	var unavailable_fixture := _fixture(1)
	var unavailable_run := unavailable_fixture.run as GameRun
	unavailable_run.party.leader().battle_skill_ids[0] = &""
	var unavailable_session := BattleSession.create(
		unavailable_fixture.encounter,
		unavailable_run,
		unavailable_fixture.database
	)
	var unavailable := unavailable_session.request_action(
		BattleActionIntent.use_skill(
			unavailable_session.player.id,
			unavailable_fixture.skill
		)
	)
	_expect(
		unavailable.rejection == BattleActionRequestResult.Rejection.SKILL_UNAVAILABLE,
		"a learned but unconfigured skill should be rejected by BattleSession"
	)
	var forged := skill.duplicate(true) as SkillDefinition
	var forged_result := session.request_action(
		BattleActionIntent.use_skill(session.player.id, forged)
	)
	_expect(
		forged_result.rejection == BattleActionRequestResult.Rejection.ACTION_INVALID,
		"a same-ID resource outside ContentDatabase should not bypass skill ownership"
	)
	var snapshot_fixture := _fixture(1)
	var snapshot_session := snapshot_fixture.session as BattleSession
	(snapshot_fixture.run as GameRun).party.leader().battle_skill_ids[0] = &""
	var snapshot_request := snapshot_session.request_action(
		BattleActionIntent.use_skill(snapshot_session.player.id, snapshot_fixture.skill)
	)
	_expect(
		snapshot_request.accepted(),
		"changing the long-lived loadout should not mutate an active BattleSession snapshot"
	)


func _test_basic_attack_resource_generation() -> void:
	var fixture := _fixture(1)
	var session := fixture.session as BattleSession
	session.player.mp = 0
	var request := session.request_action(BattleActionIntent.basic_attack(session.player.id))
	session.drain_events()
	_advance_until_active(session, session.player)
	var events := session.resolve_hit(
		session.player.id,
		request.action_instance_id,
		session.enemies[0].id
	)
	_expect(
		session.player.mp == session.player.basic_attack_resource_gain
		and _contains_kind(events, BattleEvent.Kind.MP_RESTORED),
		"the first valid basic hit should generate the configured combat resource"
	)
	var restored := session.player.mp
	session.resolve_hit(session.player.id, request.action_instance_id, session.enemies[0].id)
	_expect(
		session.player.mp == restored,
		"one basic action should generate resource at most once"
	)


func _test_equipment_build_modifiers() -> void:
	var returning_fixture := _fixture(1)
	var returning_skill := returning_fixture.skill as SkillDefinition
	var returning_modifier := ReturningProjectileModifier.new()
	returning_modifier.skill = returning_skill
	var sword_case := EquipmentDefinition.new()
	sword_case.id = &"item.test.returning_case"
	sword_case.display_name = "Returning Case"
	sword_case.slot = &"weapon"
	sword_case.battle_modifier = returning_modifier
	var returning_database := returning_fixture.database as ContentDatabase
	returning_database.items.append(sword_case)
	var returning_run := returning_fixture.run as GameRun
	returning_run.party.leader().equipment[&"weapon"] = sword_case.id
	_expect(returning_database.build_index().is_empty(), "returning projectile build should validate")
	var returning_session := BattleSession.create(
		returning_fixture.encounter,
		returning_run,
		returning_database
	)
	var returning_request := returning_session.request_action(
		BattleActionIntent.use_skill(returning_session.player.id, returning_skill)
	)
	returning_session.drain_events()
	_advance_until_active(returning_session, returning_session.player)
	_expect(
		returning_session.projectile_returns(returning_request.action_instance_id)
		and returning_session.projectile_pierces(returning_request.action_instance_id),
		"the returning sword case should snapshot a returning piercing projectile"
	)

	var refund_fixture := _fixture(3)
	var area_skill := refund_fixture.skill as SkillDefinition
	area_skill.target_rule = SkillDefinition.TargetRule.AREA
	area_skill.radius = 4.0
	var refund_modifier := AreaResourceRefundModifier.new()
	refund_modifier.skill = area_skill
	refund_modifier.required_target_count = 3
	refund_modifier.resource_refund = 4
	var sword_seal := EquipmentDefinition.new()
	sword_seal.id = &"item.test.sword_seal"
	sword_seal.display_name = "Sword Seal"
	sword_seal.slot = &"weapon"
	sword_seal.battle_modifier = refund_modifier
	var refund_database := refund_fixture.database as ContentDatabase
	refund_database.items.append(sword_seal)
	var refund_run := refund_fixture.run as GameRun
	refund_run.party.leader().equipment[&"weapon"] = sword_seal.id
	_expect(refund_database.build_index().is_empty(), "area refund build should validate")
	var refund_session := BattleSession.create(
		refund_fixture.encounter,
		refund_run,
		refund_database
	)
	var refund_request := refund_session.request_action(
		BattleActionIntent.use_skill(refund_session.player.id, area_skill)
	)
	refund_session.drain_events()
	_advance_until_active(refund_session, refund_session.player)
	var mp_after_cost := refund_session.player.mp
	var third_events: Array[BattleEvent] = []
	for target: BattleActorState in refund_session.enemies:
		third_events = refund_session.resolve_hit(
			refund_session.player.id,
			refund_request.action_instance_id,
			target.id
		)
	_expect(
		refund_session.player.mp == mp_after_cost + 4
		and _contains_kind(third_events, BattleEvent.Kind.MP_RESTORED),
		"the sword seal should refund resource once after the configured area target count"
	)


func _test_foundation_build_modifiers() -> void:
	var sharp_fixture := _fixture(1)
	var sharp_database := sharp_fixture.database as ContentDatabase
	var sharp_realm := sharp_database.realms[0]
	var sharp_modifier := BasicChainWaveModifier.new()
	sharp_modifier.chain_length = 3
	sharp_modifier.wave_damage = 7
	var sharp_foundation := DaoFoundationDefinition.new()
	sharp_foundation.id = &"foundation.test.sharp"
	sharp_foundation.display_name = "Sharp"
	sharp_foundation.required_realm = sharp_realm
	sharp_foundation.battle_modifier = sharp_modifier
	sharp_database.foundations.append(sharp_foundation)
	sharp_database.enemies[0].max_hp = 100
	var sharp_run := sharp_fixture.run as GameRun
	sharp_run.party.leader().foundation_id = sharp_foundation.id
	_expect(sharp_database.build_index().is_empty(), "sharp foundation build should validate")
	var sharp_session := BattleSession.create(
		sharp_fixture.encounter,
		sharp_run,
		sharp_database
	)
	var wave_requested := false
	for _attack_index: int in range(3):
		var request := sharp_session.request_action(
			BattleActionIntent.basic_attack(sharp_session.player.id)
		)
		sharp_session.drain_events()
		_advance_until_active(sharp_session, sharp_session.player)
		var events := sharp_session.resolve_hit(
			sharp_session.player.id,
			request.action_instance_id,
			sharp_session.enemies[0].id
		)
		wave_requested = wave_requested or _contains_action(
			events,
			BattleEvent.Kind.PROJECTILE_REQUESTED,
			&"basic_chain_wave"
		)
		_advance_until_idle(sharp_session, sharp_session.player)
	_expect(wave_requested, "the third sharp-foundation basic hit should request a sword wave")

	var flowing_fixture := _fixture(1)
	var flowing_database := flowing_fixture.database as ContentDatabase
	var flowing_realm := flowing_database.realms[0]
	var flowing_modifier := FlowingCycleModifier.new()
	flowing_modifier.resource_refund_per_skill_hit = 1
	flowing_modifier.cooldown_reduction_per_skill_hit = 0.2
	var flowing_foundation := DaoFoundationDefinition.new()
	flowing_foundation.id = &"foundation.test.flowing"
	flowing_foundation.display_name = "Flowing"
	flowing_foundation.required_realm = flowing_realm
	flowing_foundation.battle_modifier = flowing_modifier
	flowing_database.foundations.append(flowing_foundation)
	var flowing_run := flowing_fixture.run as GameRun
	flowing_run.party.leader().foundation_id = flowing_foundation.id
	_expect(flowing_database.build_index().is_empty(), "flowing foundation build should validate")
	var flowing_session := BattleSession.create(
		flowing_fixture.encounter,
		flowing_run,
		flowing_database
	)
	var flowing_skill := flowing_fixture.skill as SkillDefinition
	var flow_request := flowing_session.request_action(
		BattleActionIntent.use_skill(flowing_session.player.id, flowing_skill)
	)
	flowing_session.drain_events()
	_advance_until_active(flowing_session, flowing_session.player)
	var flow_mp := flowing_session.player.mp
	var flow_events := flowing_session.resolve_hit(
		flowing_session.player.id,
		flow_request.action_instance_id,
		flowing_session.enemies[0].id
	)
	_expect(
		flowing_session.player.mp == flow_mp + 1
		and _contains_kind(flow_events, BattleEvent.Kind.COOLDOWN_REDUCED),
		"flowing foundation skill hits should refund resource and reduce cooldowns"
	)


func _test_charge_and_pillar_stagger() -> void:
	var fixture := _fixture(1)
	var database := fixture.database as ContentDatabase
	var enemy_definition := database.enemies[0]
	enemy_definition.combat_style = EnemyDefinition.CombatStyle.CHARGER
	enemy_definition.charge_damage = 18
	enemy_definition.charge_windup_seconds = 0.08
	enemy_definition.charge_active_seconds = 0.2
	enemy_definition.charge_recovery_seconds = 0.1
	enemy_definition.charge_cooldown_seconds = 1.0
	enemy_definition.charge_stagger_seconds = 0.25
	enemy_definition.charge_staggers_on_pillar = true
	_expect(database.build_index().is_empty(), "charger content should validate")
	var session := BattleSession.create(fixture.encounter, fixture.run, database)
	var charger := session.enemies[0]
	var request := session.request_action(
		BattleActionIntent.charge(charger.id, session.player.id)
	)
	_expect(request.accepted(), "a configured charger should accept its charge action")
	session.drain_events()
	_advance_until_active(session, charger)
	_expect(
		session.resolve_pillar_contact(
			charger.id,
			request.action_instance_id + 1,
			&"pillar.test"
		).is_empty(),
		"pillar contact should reject the wrong charge action instance"
	)
	var events := session.resolve_pillar_contact(
		charger.id,
		request.action_instance_id,
		&"pillar.test"
	)
	_expect(
		session.is_pillar_used(&"pillar.test")
		and charger.current_action == null
		and charger.stagger_remaining_seconds > 0.0
		and _contains_kind(events, BattleEvent.Kind.PILLAR_CONSUMED)
		and _contains_kind(events, BattleEvent.Kind.STAGGER_STARTED),
		"a valid active charge should consume one pillar and enter timed stagger"
	)
	_expect(
		session.resolve_pillar_contact(
			charger.id,
			request.action_instance_id,
			&"pillar.test"
		).is_empty(),
		"the same pillar should not stagger a charge twice"
	)
	var busy := session.request_action(BattleActionIntent.basic_attack(charger.id))
	_expect(
		busy.rejection == BattleActionRequestResult.Rejection.ACTOR_BUSY,
		"a staggered actor should not start another action"
	)
	var recovered := false
	for _step: int in range(30):
		var advanced := session.advance(BattleSession.FIXED_STEP_SECONDS)
		recovered = recovered or _contains_kind(advanced, BattleEvent.Kind.STAGGER_ENDED)
	_expect(
		recovered and charger.stagger_remaining_seconds <= 0.0,
		"stagger should end deterministically in fixed rule time"
	)
	charger.charge_staggers_on_pillar = false
	for _step: int in range(40):
		session.advance(BattleSession.FIXED_STEP_SECONDS)
	var ordinary_charge := session.request_action(
		BattleActionIntent.charge(charger.id, session.player.id)
	)
	_expect(ordinary_charge.accepted(), "a recovered charger should charge again")
	session.drain_events()
	_advance_until_active(session, charger)
	var ordinary_events := session.resolve_pillar_contact(
		charger.id,
		ordinary_charge.action_instance_id,
		&"pillar.ordinary"
	)
	_expect(
		ordinary_events.is_empty()
		and not session.is_pillar_used(&"pillar.ordinary")
		and charger.current_action != null,
		"charge style alone should not imply the lantern-pillar stagger mechanic"
	)


func _test_dodge_invulnerability() -> void:
	var fixture := _fixture(1)
	var session := fixture.session as BattleSession
	var dodge := session.request_action(BattleActionIntent.dodge(session.player.id))
	_expect(dodge.accepted(), "an idle actor should be able to dodge")
	var dodge_events := session.drain_events()
	_expect(
		_contains_kind(dodge_events, BattleEvent.Kind.DODGE_STARTED)
		and _contains_kind(dodge_events, BattleEvent.Kind.COOLDOWN_STARTED),
		"dodge should emit its active-window and cooldown contracts"
	)
	var enemy := session.enemies[0]
	var attack := session.request_action(
		BattleActionIntent.basic_attack(enemy.id, session.player.id)
	)
	session.drain_events()
	for _step: int in range(120):
		session.advance(BattleSession.FIXED_STEP_SECONDS)
		if (
			session.player.current_action != null
			and session.player.current_action.phase == BattleActionState.Phase.ACTIVE
			and enemy.current_action != null
			and enemy.current_action.phase == BattleActionState.Phase.ACTIVE
		):
			break
	var hp_before := session.player.hp
	var hit_events := session.resolve_hit(enemy.id, attack.action_instance_id, session.player.id)
	_expect(
		session.player.hp == hp_before
		and _contains_kind(hit_events, BattleEvent.Kind.DODGED),
		"a hit candidate inside the dodge active window should deal no damage"
	)
	_advance_until_idle(session, session.player)
	_expect(
		session.resolve_hit(enemy.id, attack.action_instance_id, session.player.id).is_empty()
		and session.player.hp == hp_before,
		"a dodged action must not apply the same hit after invulnerability ends"
	)


func _test_projectile_hit_after_action_recovery() -> void:
	var fixture := _fixture(1)
	var session := fixture.session as BattleSession
	var skill := fixture.skill as SkillDefinition
	var target := session.enemies[0]
	var request := session.request_action(
		BattleActionIntent.use_skill(session.player.id, skill, target.id)
	)
	_expect(request.accepted(), "a projectile skill should start normally")
	session.drain_events()
	_advance_until_idle(session, session.player)
	var hp_before := target.hp
	var events := session.resolve_hit(
		session.player.id,
		request.action_instance_id,
		target.id
	)
	_expect(
		target.hp == hp_before - 9 and _contains_kind(events, BattleEvent.Kind.DAMAGE),
		"a launched projectile should remain valid after the caster recovers"
	)
	_expect(
		session.resolve_hit(
			session.player.id,
			request.action_instance_id,
			target.id
		).is_empty(),
		"a launched projectile action should still resolve at most once"
	)


func _test_timed_status_ticks() -> void:
	var fixture := _fixture(1)
	var session := fixture.session as BattleSession
	var status := fixture.status as StatusDefinition
	var target := session.enemies[0]
	var hp_before := target.hp
	var applied := session.apply_status(target.id, status)
	_expect(
		applied.size() == 1 and applied[0].kind == BattleEvent.Kind.STATUS_APPLIED,
		"applying a valid timed status should emit STATUS_APPLIED"
	)
	_advance_steps(session, 29)
	_expect(target.hp == hp_before, "a timed status should not tick before its interval")
	var tick_events: Array[BattleEvent] = []
	for _step: int in range(2):
		tick_events.append_array(session.advance(BattleSession.FIXED_STEP_SECONDS))
	_expect(
		target.hp == hp_before - status.periodic_damage
		and _contains_kind(tick_events, BattleEvent.Kind.STATUS_TICK),
		"a timed status should tick after its interval"
	)
	_advance_steps(session, 30)
	_expect(
		target.hp == hp_before - status.periodic_damage * 2,
		"status ticks should use fixed rule time"
	)
	_advance_steps(session, 7)
	_expect(not target.statuses.has(status.id), "expired statuses should leave BattleActorState")
