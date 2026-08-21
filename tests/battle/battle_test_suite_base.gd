class_name BattleTestSuiteBase
extends RefCounted

var _failures: PackedStringArray = []


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
	skill.usable_in_battle = true
	skill.effects.append(damage)
	var healing_item := ItemDefinition.new()
	healing_item.id = &"item.test.heal"
	healing_item.display_name = "Test Heal"
	healing_item.max_stack = 9
	healing_item.usable_in_field = true
	healing_item.usable_in_battle = true
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
	var realm := CultivationRealmDefinition.new()
	realm.id = &"realm.test.qi"
	realm.display_name = "Test Qi"
	realm.max_layer = 2
	realm.layer_cultivation_costs = PackedInt32Array([10])
	actor.initial_realm = realm
	actor.initial_skills.append(skill)
	var enemy_definition := EnemyDefinition.new()
	enemy_definition.id = &"enemy.test.melee"
	enemy_definition.display_name = "Test Enemy"
	enemy_definition.max_hp = 10
	enemy_definition.attack = 20
	enemy_definition.attack_windup_seconds = 0.08
	enemy_definition.cultivation_reward = 2
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
	database.realms.append(realm)
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


func _contains_action(
	events: Array[BattleEvent],
	kind: BattleEvent.Kind,
	action_id: StringName
) -> bool:
	for event: BattleEvent in events:
		if event.kind == kind and event.action_id == action_id:
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
