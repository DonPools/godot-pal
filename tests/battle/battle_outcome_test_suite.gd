class_name BattleOutcomeTestSuite
extends BattleTestSuiteBase


func run() -> PackedStringArray:
	_test_victory_and_idempotent_rewards()
	_test_reward_policy_boundaries()
	_test_escape_commits_consumption_only()
	_test_defeat_commits_party_state()
	return _failures


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
		and committed.cultivation_reward == 4
		and run.party.leader().cultivation_points == 4
		and committed.money_reward == 6
		and run.inventory.quantity(item.id) == 2,
		"Victory should commit duration, defeated IDs, money and configured drops"
	)
	var repeated := session.commit_result()
	_expect(
		repeated == committed
		and run.economy.money == money_after
		and run.party.leader().cultivation_points == 4
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
	run.party.leader().battle_item_id = item.id
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
