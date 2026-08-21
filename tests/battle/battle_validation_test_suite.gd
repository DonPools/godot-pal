class_name BattleValidationTestSuite
extends BattleTestSuiteBase


func run() -> PackedStringArray:
	_test_realtime_content_validation()
	_test_invalid_content_does_not_spend_resources()
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
	for unsupported_rule: SkillDefinition.TargetRule in [
		SkillDefinition.TargetRule.SELF,
		SkillDefinition.TargetRule.SINGLE_ENEMY,
		SkillDefinition.TargetRule.POINT,
	]:
		var unsupported_target := _fixture(1)
		(unsupported_target.skill as SkillDefinition).target_rule = unsupported_rule
		_expect(
			_contains_text(
				(unsupported_target.database as ContentDatabase).build_index(),
				"unsupported battle target rule"
			),
			"unsupported battle skill target rules should fail content validation"
		)
	var empty_skill := _fixture(1)
	(empty_skill.skill as SkillDefinition).effects.clear()
	_expect(
		_contains_text(
			(empty_skill.database as ContentDatabase).build_index(),
			"usable in battle but has no GameEffect"
		),
		"battle skills without effects should fail content validation"
	)
	var field_skill := _fixture(1)
	(field_skill.skill as SkillDefinition).usable_in_field = true
	_expect(
		_contains_text(
			(field_skill.database as ContentDatabase).build_index(),
			"cannot currently be used in the field"
		),
		"field-usable skills should fail until a field execution path exists"
	)
	var empty_item := _fixture(1)
	(empty_item.healing_item as ItemDefinition).effects.clear()
	_expect(
		_contains_text(
			(empty_item.database as ContentDatabase).build_index(),
			"usable but has no GameEffect"
		),
		"usable items without effects should fail content validation"
	)
	var damaging_item := _fixture(1)
	var item_damage := DamageEffect.new()
	item_damage.id = &"effect.test.invalid_item_damage"
	(damaging_item.healing_item as ItemDefinition).effects.assign([item_damage])
	_expect(
		_contains_text(
			(damaging_item.database as ContentDatabase).build_index(),
			"Item item.test.heal contains an unsupported GameEffect"
		),
		"items should reject combat-only damage effects"
	)
	for unsupported_effect: GameEffect in [HealEffect.new(), RestoreMpEffect.new()]:
		var unsupported_skill := _fixture(1)
		unsupported_effect.id = &"effect.test.invalid_skill_effect"
		(unsupported_skill.skill as SkillDefinition).effects.assign([unsupported_effect])
		_expect(
			_contains_text(
				(unsupported_skill.database as ContentDatabase).build_index(),
				"Skill skill.test.strike contains an unsupported GameEffect"
			),
			"battle skills should reject non-damage effects"
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


func _test_invalid_content_does_not_spend_resources() -> void:
	var empty_skill_fixture := _fixture(1)
	var empty_skill_session := empty_skill_fixture.session as BattleSession
	(empty_skill_fixture.skill as SkillDefinition).effects.clear()
	var mp_before := empty_skill_session.player.mp
	var empty_skill_request := empty_skill_session.request_action(
		BattleActionIntent.use_skill(
			empty_skill_session.player.id,
			empty_skill_fixture.skill
		)
	)
	_expect(
		empty_skill_request.rejection == BattleActionRequestResult.Rejection.ACTION_INVALID
		and empty_skill_session.player.mp == mp_before,
		"empty battle skills should be rejected before MP is spent"
	)

	var unsupported_target_fixture := _fixture(1)
	var unsupported_target_session := unsupported_target_fixture.session as BattleSession
	(unsupported_target_fixture.skill as SkillDefinition).target_rule = (
		SkillDefinition.TargetRule.SINGLE_ENEMY
	)
	mp_before = unsupported_target_session.player.mp
	var unsupported_target_request := unsupported_target_session.request_action(
		BattleActionIntent.use_skill(
			unsupported_target_session.player.id,
			unsupported_target_fixture.skill
		)
	)
	_expect(
		unsupported_target_request.rejection
		== BattleActionRequestResult.Rejection.ACTION_INVALID
		and unsupported_target_session.player.mp == mp_before,
		"unsupported battle skill targets should be rejected before MP is spent"
	)

	var empty_item_fixture := _fixture(1)
	var empty_item_run := empty_item_fixture.run as GameRun
	var empty_item := empty_item_fixture.healing_item as ItemDefinition
	empty_item_run.inventory.add_item(empty_item, 1)
	empty_item_run.party.leader().battle_item_id = empty_item.id
	var empty_item_session := BattleSession.create(
		empty_item_fixture.encounter,
		empty_item_run,
		empty_item_fixture.database
	)
	empty_item.effects.clear()
	var empty_item_request := empty_item_session.request_action(
		BattleActionIntent.use_item(
			empty_item_session.player.id,
			empty_item,
			empty_item_session.player.id
		)
	)
	_expect(
		empty_item_request.rejection == BattleActionRequestResult.Rejection.ACTION_INVALID
		and empty_item_session.battle_item_quantity() == 1,
		"empty battle items should be rejected before inventory is consumed"
	)
