class_name BattleSessionTestSuite
extends RefCounted

var _failures: PackedStringArray = []


func run() -> PackedStringArray:
	_test_realtime_content_validation()
	_test_action_timeline_and_fixed_step()
	_test_skill_rejections_and_effects()
	_test_projectile_hit_after_action_recovery()
	_test_dodge_invulnerability()
	_test_timed_status_ticks()
	_test_victory_and_idempotent_rewards()
	_test_reward_policy_boundaries()
	_test_escape_commits_consumption_only()
	_test_defeat_commits_party_state()
	return _failures


func _test_realtime_content_validation() -> void:
	var valid := _fixture(1)
	var valid_errors := (valid.database as ContentDatabase).build_index()
	_expect(valid_errors.is_empty(), "valid realtime combat content should pass ContentDatabase")
	var invalid_skill := _fixture(1)
	var skill := invalid_skill.skill as SkillDefinition
	skill.target_rule = SkillDefinition.TargetRule.AREA
	skill.radius = 0.0
	_expect(
		_contains_text(
			(invalid_skill.database as ContentDatabase).build_index(),
			"invalid realtime combat values"
		),
		"AREA skills without a radius should fail content validation"
	)
	var invalid_scene := _fixture(1)
	var enemy := (invalid_scene.database as ContentDatabase).enemies[0]
	enemy.character_scene = load(
		"res://tests/fixtures/not_character_body_3d.tscn"
	) as PackedScene
	_expect(
		_contains_text(
			(invalid_scene.database as ContentDatabase).build_index(),
			"root is not CharacterBody3D"
		),
		"enemy scenes should require a CharacterBody3D root"
	)
	var invalid_spawn := _fixture(1)
	var encounter := invalid_spawn.encounter as BattleEncounter
	encounter.enemies[0].spawn_offset = Vector3(50.0, 0.0, 0.0)
	_expect(
		_contains_text(
			(invalid_spawn.database as ContentDatabase).build_index(),
			"invalid spawn configuration"
		),
		"enemy spawn offsets should remain inside the encounter boundary"
	)
	var duplicate := _fixture(1)
	var duplicate_encounter := duplicate.encounter as BattleEncounter
	duplicate_encounter.enemies.append(duplicate_encounter.enemies[0].duplicate(true))
	_expect(
		_contains_text(
			(duplicate.database as ContentDatabase).build_index(),
			"empty or repeated enemy instance ID"
		),
		"encounters should reject repeated stable enemy instance IDs"
	)


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
	var other_session := other.session as BattleSession
	var insufficient := other_session.request_action(
		BattleActionIntent.use_skill(other_session.player.id, expensive)
	)
	_expect(
		insufficient.rejection == BattleActionRequestResult.Rejection.INSUFFICIENT_RESOURCE,
		"skills should reject requests without enough MP"
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


func _test_victory_and_idempotent_rewards() -> void:
	var fixture := _fixture(2)
	var session := fixture.session as BattleSession
	for target: BattleActorState in session.enemies:
		var request := session.request_action(BattleActionIntent.basic_attack(session.player.id))
		_expect(request.accepted(), "each victory attack should be accepted")
		session.drain_events()
		_advance_until_active(session, session.player)
		session.resolve_hit(session.player.id, request.action_instance_id, target.id)
		if target != session.enemies[-1]:
			_expect(not session.finished, "victory should wait for every required enemy")
			_advance_until_idle(session, session.player)
	_expect(
		session.finished and session.outcome == BattleResult.Outcome.VICTORY,
		"defeating every enemy should finish once with Victory"
	)
	var run := fixture.run as GameRun
	var committed := session.commit_result()
	var money_after := run.economy.money
	var item := fixture.drop_item as ItemDefinition
	_expect(
		committed.committed
		and committed.duration_msec > 0
		and committed.defeated_enemy_ids.size() == 2
		and committed.experience_reward == 4
		and run.party.leader().experience == 4
		and committed.money_reward == 6
		and run.inventory.quantity(item.id) == 2,
		"Victory should commit duration, defeated IDs, money and configured drops"
	)
	var repeated := session.commit_result()
	_expect(
		repeated == committed
		and run.economy.money == money_after
		and run.party.leader().experience == 4
		and run.inventory.quantity(item.id) == 2,
		"result commit should be idempotent"
	)


func _test_reward_policy_boundaries() -> void:
	var atomic_fixture := _fixture(2)
	var atomic_session := atomic_fixture.session as BattleSession
	var atomic_item := atomic_fixture.drop_item as ItemDefinition
	atomic_item.max_stack = 1
	_defeat_all_enemies(atomic_session)
	var atomic_result := atomic_session.commit_result()
	var atomic_run := atomic_fixture.run as GameRun
	_expect(
		atomic_run.inventory.quantity(atomic_item.id) == 0
		and atomic_result.dropped_items.is_empty()
		and atomic_result.rejected_dropped_items.get(atomic_item.id, 0) == 2,
		"ALL_OR_NOTHING should reject the complete encounter drop group"
	)
	var partial_fixture := _fixture(2)
	var partial_session := partial_fixture.session as BattleSession
	var partial_item := partial_fixture.drop_item as ItemDefinition
	partial_item.max_stack = 1
	(partial_fixture.encounter as BattleEncounter).reward_policy = (
		RewardPolicy.Value.ALLOW_PARTIAL
	)
	_defeat_all_enemies(partial_session)
	var partial_result := partial_session.commit_result()
	var partial_run := partial_fixture.run as GameRun
	_expect(
		partial_run.inventory.quantity(partial_item.id) == 1
		and partial_result.dropped_items.get(partial_item.id, 0) == 1
		and partial_result.rejected_dropped_items.get(partial_item.id, 0) == 1,
		"ALLOW_PARTIAL should commit capacity and record the rejected remainder"
	)


func _test_escape_commits_consumption_only() -> void:
	var fixture := _fixture(1)
	var session := fixture.session as BattleSession
	var run := fixture.run as GameRun
	var item := fixture.healing_item as ItemDefinition
	run.inventory.add_item(item, 1)
	# Recreate so the session snapshots the inventory after the item is present.
	session = BattleSession.create(fixture.encounter, run, fixture.database)
	session.player.hp = 50
	var request := session.request_action(
		BattleActionIntent.use_item(session.player.id, item, session.player.id)
	)
	_expect(request.accepted(), "an available battle item should be accepted")
	session.drain_events()
	_advance_until_active(session, session.player)
	session.resolve_hit(session.player.id, request.action_instance_id, session.player.id)
	var result := session.finish_escape()
	_expect(result.outcome == BattleResult.Outcome.ESCAPED, "escape should produce Escaped")
	var money_before := run.economy.money
	result = session.commit_result()
	_expect(
		result.committed
		and run.party.leader().hp == 75
		and run.inventory.quantity(item.id) == 0
		and run.economy.money == money_before,
		"Escaped should commit HP and item consumption without victory rewards"
	)


func _test_defeat_commits_party_state() -> void:
	var fixture := _fixture(1)
	var session := fixture.session as BattleSession
	session.player.hp = 5
	var enemy := session.enemies[0]
	var request := session.request_action(BattleActionIntent.basic_attack(enemy.id, session.player.id))
	_expect(request.accepted(), "an alive enemy should be able to request an action")
	session.drain_events()
	_advance_until_active(session, enemy)
	session.resolve_hit(enemy.id, request.action_instance_id, session.player.id)
	_expect(
		session.finished and session.outcome == BattleResult.Outcome.DEFEAT,
		"player death should finish once with Defeat"
	)
	var run := fixture.run as GameRun
	var result := session.commit_result()
	_expect(
		result.committed and run.party.leader().hp == 0 and run.economy.money == 0,
		"Defeat should commit party state without victory rewards"
	)


func _fixture(enemy_count: int) -> Dictionary:
	var damage := DamageEffect.new()
	damage.id = &"effect.test.damage"
	damage.amount = 9
	var heal := HealEffect.new()
	heal.id = &"effect.test.heal"
	heal.amount = 25
	var skill := SkillDefinition.new()
	skill.id = &"skill.test.strike"
	skill.display_name = "Test Strike"
	skill.mp_cost = 4
	skill.cooldown_seconds = 1.0
	skill.cast_seconds = 0.1
	skill.active_seconds = 0.1
	skill.recovery_seconds = 0.1
	skill.effects.append(damage)
	var healing_item := ItemDefinition.new()
	healing_item.id = &"item.test.heal"
	healing_item.display_name = "Test Heal"
	healing_item.max_stack = 9
	healing_item.effects.append(heal)
	var drop_item := ItemDefinition.new()
	drop_item.id = &"item.test.drop"
	drop_item.display_name = "Test Drop"
	drop_item.max_stack = 9
	drop_item.usable_in_battle = false
	var status := StatusDefinition.new()
	status.id = &"status.test.burn"
	status.display_name = "Test Burn"
	status.duration_seconds = 1.1
	status.tick_interval_seconds = 0.5
	status.periodic_damage = 2
	var actor := ActorDefinition.new()
	actor.id = &"actor.test.hero"
	actor.display_name = "Test Hero"
	actor.base_max_hp = 100
	actor.base_max_mp = 20
	actor.initial_skills.append(skill)
	var enemy_definition := EnemyDefinition.new()
	enemy_definition.id = &"enemy.test.melee"
	enemy_definition.display_name = "Test Enemy"
	enemy_definition.max_hp = 10
	enemy_definition.attack = 20
	enemy_definition.attack_windup_seconds = 0.08
	enemy_definition.experience_reward = 2
	enemy_definition.money_reward = 3
	enemy_definition.drop_item = drop_item
	enemy_definition.drop_quantity = 1
	enemy_definition.character_scene = load(
		"res://tests/battle/enemy_character_fixture.tscn"
	) as PackedScene
	enemy_definition.strategy = BasicAttackStrategy.new()
	var encounter := BattleEncounter.new()
	encounter.id = &"encounter.test.group"
	encounter.display_name = "Test Group"
	for index: int in range(enemy_count):
		var entry := EncounterEnemy.new()
		entry.enemy = enemy_definition
		entry.instance_id = StringName("enemy.test.%d" % index)
		entry.spawn_offset = Vector3(float(index), 0.0, 0.0)
		encounter.enemies.append(entry)
	var database := ContentDatabase.new()
	database.actors.append(actor)
	database.items.assign([healing_item, drop_item])
	database.skills.append(skill)
	database.statuses.append(status)
	database.enemies.append(enemy_definition)
	database.encounters.append(encounter)
	database.starting_party.append(actor)
	database.starting_money = 0
	database.build_index()
	var run := GameRun.new_game(database, 12_345)
	return {
		"database": database,
		"run": run,
		"skill": skill,
		"status": status,
		"healing_item": healing_item,
		"drop_item": drop_item,
		"encounter": encounter,
		"session": BattleSession.create(encounter, run, database),
	}


func _advance_until_active(session: BattleSession, actor: BattleActorState) -> void:
	for _step: int in range(120):
		if actor.current_action != null and actor.current_action.phase == BattleActionState.Phase.ACTIVE:
			return
		session.advance(BattleSession.FIXED_STEP_SECONDS)
	_expect(false, "action should reach its active phase within two seconds")


func _advance_until_idle(session: BattleSession, actor: BattleActorState) -> void:
	for _step: int in range(120):
		if actor.current_action == null:
			return
		session.advance(BattleSession.FIXED_STEP_SECONDS)
	_expect(false, "action should finish within two seconds")


func _advance_steps(session: BattleSession, count: int) -> void:
	for _step: int in range(count):
		session.advance(BattleSession.FIXED_STEP_SECONDS)


func _defeat_all_enemies(session: BattleSession) -> void:
	for target: BattleActorState in session.enemies:
		var request := session.request_action(BattleActionIntent.basic_attack(session.player.id))
		session.drain_events()
		_advance_until_active(session, session.player)
		session.resolve_hit(session.player.id, request.action_instance_id, target.id)
		if not session.finished:
			_advance_until_idle(session, session.player)


func _contains_kind(events: Array[BattleEvent], kind: BattleEvent.Kind) -> bool:
	for event: BattleEvent in events:
		if event.kind == kind:
			return true
	return false


func _count_kind(events: Array[BattleEvent], kind: BattleEvent.Kind) -> int:
	var count := 0
	for event: BattleEvent in events:
		if event.kind == kind:
			count += 1
	return count


func _contains_text(messages: PackedStringArray, fragment: String) -> bool:
	for message: String in messages:
		if message.contains(fragment):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
