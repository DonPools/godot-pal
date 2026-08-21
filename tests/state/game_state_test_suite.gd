class_name GameStateTestSuite
extends RefCounted

const TEST_SAVE := "res://tests/.tmp_roadside_save.json"
const TEST_SLOTS := "res://tests/.tmp_roadside_slots"

var _failures: PackedStringArray = []


func run() -> PackedStringArray:
	_test_random_state()
	_test_cultivation_rules()
	_test_equipment_transaction()
	_test_inventory_and_loadout_transactions()
	_test_item_delivery()
	_test_game_run_round_trip()
	_test_save_baseline_fixtures()
	_test_save_service()
	return _failures


func _test_random_state() -> void:
	var first := RandomState.new()
	first.initialize(117)
	first.roll_percent(50)
	var restored := RandomState.new()
	_expect(restored.restore(first.to_dictionary()), "random source should restore from save data")
	_expect(
		first.roll_percent(50) == restored.roll_percent(50),
		"restored random source should continue the same deterministic sequence"
	)


func _test_cultivation_rules() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	_expect(database.build_index().is_empty(), "cultivation test database should validate")
	var run := GameRun.new_game(database, 771)
	var leader := run.party.leader()
	var actor := database.actor(leader.definition_id)
	_expect(
		leader.realm_id == &"realm.qi_refining"
		and leader.realm_layer == 7
		and leader.cultivation_points == 0,
		"new MVP game should start at qi refining layer seven"
	)
	_expect(
		leader.hp == CultivationRules.max_hp(actor, leader, database)
		and leader.mp == CultivationRules.max_mp(actor, leader, database),
		"new actors should start with cultivation-derived full HP and MP"
	)
	var cadence := GameRun.new_game(database, 770).party.leader()
	var cadence_encounters: Array[StringName] = [
		&"encounter.roadside.lantern_pass.first_pack",
		&"encounter.roadside.lantern_pass.second_pack",
		&"encounter.roadside.lantern_pass.third_pack",
		&"encounter.roadside.lantern_pass.elite",
		&"encounter.roadside.lantern_pass_beast",
	]
	var expected_layers := PackedInt32Array([7, 8, 9, 9, 9])
	var expected_points := PackedInt32Array([32, 40, 50, 90, 100])
	for encounter_index: int in range(cadence_encounters.size()):
		var encounter := database.encounter(cadence_encounters[encounter_index])
		var reward := 0
		for entry: EncounterEnemy in encounter.enemies:
			reward += entry.enemy.cultivation_reward
		CultivationRules.gain_cultivation(cadence, reward, database)
		_expect(
			cadence.realm_layer == expected_layers[encounter_index]
			and cadence.cultivation_points == expected_points[encounter_index],
			"lantern encounter %s should produce the authored cultivation cadence"
			% cadence_encounters[encounter_index]
		)
	_expect(
		CultivationRules.is_ready_for_breakthrough(cadence, database),
		"the five pre-foundation lantern victories should exactly reach breakthrough readiness"
	)
	var first_gain := CultivationRules.gain_cultivation(leader, 60, database)
	_expect(
		first_gain.succeeded()
		and first_gain.layers_gained == 1
		and leader.realm_layer == 8
		and leader.cultivation_points == 0,
		"cultivation should consume the configured layer cost"
	)
	CultivationRules.gain_cultivation(leader, 170, database)
	_expect(
		leader.realm_layer == 9
		and leader.cultivation_points == 100
		and CultivationRules.is_ready_for_breakthrough(leader, database),
		"max-layer cultivation should cap at the breakthrough requirement"
	)
	var foundation := database.foundation(&"foundation.sharp_metal")
	var breakthrough := CultivationRules.breakthrough(leader, foundation, database)
	_expect(
		breakthrough.succeeded()
		and leader.realm_id == &"realm.foundation_establishment"
		and leader.realm_layer == 1
		and leader.foundation_id == foundation.id
		and leader.cultivation_points == 0,
		"a valid foundation should atomically advance the actor into foundation establishment"
	)
	var legacy := GameRun.new_game(database, 772).to_dictionary()
	legacy["save_version"] = GameRun.THREE_DIMENSIONAL_SAVE_VERSION
	var legacy_actor: Dictionary = legacy["party"]["members"][0]
	legacy_actor.erase("realm_id")
	legacy_actor.erase("realm_layer")
	legacy_actor.erase("cultivation_points")
	legacy_actor.erase("foundation_id")
	legacy_actor["level"] = 8
	legacy_actor["experience"] = 5
	var migrated := GameRun.from_dictionary(legacy, database)
	_expect(
		migrated != null
		and migrated.party.leader().realm_id == &"realm.qi_refining"
		and migrated.party.leader().realm_layer == 8
		and migrated.party.leader().cultivation_points == 5,
		"version four level and experience should migrate into cultivation state"
	)
	var catalyst_run := GameRun.new_game(database, 773)
	var catalyst_actor := catalyst_run.party.leader()
	CultivationRules.gain_cultivation(catalyst_actor, 230, database)
	var catalyst := database.item(&"item.roadside.qi_eating_stone_heart")
	var missing := CultivationTransaction.breakthrough(
		catalyst_run,
		database.foundation(&"foundation.flowing_water"),
		catalyst,
		database
	)
	_expect(
		missing.outcome == CultivationResult.Outcome.CATALYST_REQUIRED
		and catalyst_actor.realm_id == &"realm.qi_refining",
		"breakthrough transaction should leave cultivation unchanged without its catalyst"
	)
	catalyst_run.inventory.add_item(catalyst, 1)
	var completed := CultivationTransaction.breakthrough(
		catalyst_run,
		database.foundation(&"foundation.flowing_water"),
		catalyst,
		database
	)
	_expect(
		completed.succeeded()
		and catalyst_run.inventory.quantity(catalyst.id) == 0
		and &"skill.roadside.origin_sword_array" in catalyst_actor.learned_skill_ids
		and catalyst_actor.battle_skill_ids[2] == &"skill.roadside.origin_sword_array"
		and catalyst_actor.hp == CultivationRules.max_hp(
			actor,
			catalyst_actor,
			database
		),
		"breakthrough transaction should consume one catalyst, grant the ultimate, and refill derived stats"
	)


func _test_equipment_transaction() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	_expect(database.build_index().is_empty(), "equipment transaction database should validate")
	var run := GameRun.new_game(database, 881)
	run.location.map_id = &"map.roadside.north_slope_wilds"
	var leader := run.party.leader()
	var sword_case := database.item(&"item.roadside.returning_sword_case") as EquipmentDefinition
	var sword_seal := database.item(&"item.roadside.suppressing_sword_seal") as EquipmentDefinition
	run.inventory.add_item(sword_case, 1)
	run.inventory.add_item(sword_seal, 1)
	var first := EquipmentTransaction.equip(run, leader, sword_case, database)
	_expect(
		first.succeeded()
		and leader.equipment.get(&"weapon") == sword_case.id
		and run.inventory.quantity(sword_case.id) == 0,
		"equipping a carried weapon should remove it from inventory and update ActorState"
	)
	var replacement := EquipmentTransaction.equip(run, leader, sword_seal, database)
	_expect(
		replacement.succeeded()
		and replacement.returned_item_id == sword_case.id
		and leader.equipment.get(&"weapon") == sword_seal.id
		and run.inventory.quantity(sword_case.id) == 1
		and run.inventory.quantity(sword_seal.id) == 0,
		"replacing a weapon should atomically return the previous equipment"
	)
	var unequipped := EquipmentTransaction.unequip(run, leader, &"weapon", database)
	_expect(
		unequipped.outcome == EquipmentResult.Outcome.UNEQUIPPED
		and not leader.equipment.has(&"weapon")
		and run.inventory.quantity(sword_seal.id) == 1,
		"unequipping should atomically return the current weapon to inventory"
	)
	_expect(
		database.validate_game_run(run).is_empty(),
		"equipped MVP build state should remain valid save content"
	)


func _test_inventory_and_loadout_transactions() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	_expect(database.build_index().is_empty(), "inventory/loadout database should validate")
	var run := GameRun.new_game(database, 884)
	run.location.map_id = &"map.roadside.lantern_pass"
	var leader := run.party.leader()
	var herb := database.item(&"item.roadside.fanqing_grass")
	var catalyst := database.item(&"item.roadside.qi_eating_stone_heart")
	var medicine := database.item(&"item.roadside.wound_powder")
	run.inventory.max_distinct_items = 1
	_expect(run.inventory.add_item(herb, 1).succeeded(), "the first regular item should use capacity")
	_expect(
		run.inventory.add_item(catalyst, 1).succeeded()
		and run.inventory.occupied_capacity() == 1,
		"key items should not consume regular inventory capacity"
	)
	_expect(
		not run.inventory.add_item(medicine, 1).succeeded()
		and run.inventory.quantity(medicine.id) == 0,
		"a second regular item type should be rejected at capacity"
	)
	_expect(
		ItemDiscardTransaction.discard(run, catalyst, 1).outcome
		== ItemDiscardResult.Outcome.NOT_DISCARDABLE,
		"key items should not be discardable"
	)
	_expect(
		ItemDiscardTransaction.discard(run, herb, 1).succeeded()
		and run.inventory.add_item(medicine, 2).succeeded(),
		"discarding a regular item should free capacity atomically"
	)
	var quick := BattleItemLoadoutTransaction.assign(run, leader, medicine, database)
	_expect(
		quick.outcome == BattleItemLoadoutResult.Outcome.ASSIGNED
		and leader.battle_item_id == medicine.id,
		"a carried battle consumable should be assignable to the action bar"
	)
	var wind := database.skill(&"skill.roadside.wind_edge")
	var ultimate := database.skill(&"skill.roadside.origin_sword_array")
	var unlearned := SkillLoadoutTransaction.assign(leader, ultimate, 2, database)
	_expect(
		unlearned.outcome == SkillLoadoutResult.Outcome.SKILL_NOT_LEARNED,
		"unlearned skills should not enter battle slots"
	)
	var moved := SkillLoadoutTransaction.assign(leader, wind, 2, database)
	_expect(
		moved.succeeded()
		and leader.battle_skill_ids[0].is_empty()
		and leader.battle_skill_ids[2] == wind.id,
		"assigning an equipped skill elsewhere should move it without duplication"
	)
	var learned := SkillLearningTransaction.learn(leader, ultimate, database)
	_expect(
		learned.succeeded()
		and learned.auto_equipped
		and learned.slot_index == 0
		and leader.learned_skill_ids.has(ultimate.id)
		and leader.battle_skill_ids[0] == ultimate.id,
		"learning a skill should fill the first empty battle slot"
	)
	_expect(
		database.validate_game_run(run).is_empty(),
		"inventory and loadout transactions should leave a valid GameRun"
	)


func _test_item_delivery() -> void:
	var item := load("res://content/items/fanqing_grass.tres") as ItemDefinition
	var run := GameRun.new()
	run.economy.money = 18
	var missing := ItemDeliveryTransaction.exchange(run, item, 2, 12)
	_expect(
		missing.outcome == DeliveryResult.Outcome.INSUFFICIENT_ITEMS
		and run.economy.money == 18,
		"failed delivery should not change money"
	)
	run.inventory.add_item(item, 2)
	var completed := ItemDeliveryTransaction.exchange(run, item, 2, 12)
	_expect(
		completed.completed()
		and run.inventory.quantity(item.id) == 0
		and run.economy.money == 30,
		"delivery should remove exact items and add wages atomically"
	)


func _test_game_run_round_trip() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	database.build_index()
	var run := GameRun.new_game(database)
	run.location.map_id = &"map.roadside.shop"
	run.location.spawn_id = &"default"
	run.location.position = Vector3(48, 3, 192)
	run.location.direction = &"east"
	run.location.has_exact_position = true
	run.randomness.initialize(9182)
	run.randomness.roll_percent(50)
	var medicine := database.item(&"item.roadside.wound_powder")
	run.inventory.add_item(medicine, 1)
	run.party.leader().battle_item_id = medicine.id
	var restored := GameRun.from_dictionary(run.to_dictionary(), database)
	_expect(restored != null, "GameRun should round-trip the new content version")
	if restored == null:
		return
	_expect(
		restored.party.leader_id == &"actor.roadside.traveler",
		"GameRun should preserve the original traveler"
	)
	_expect(restored.location.map_id == &"map.roadside.shop", "location should round-trip")
	_expect(restored.location.position == Vector3(48, 3, 192), "exact 3D position should round-trip")
	_expect(
		restored.party.leader().battle_skill_ids == run.party.leader().battle_skill_ids
		and restored.party.leader().battle_item_id == medicine.id,
		"v6 should round-trip learned skills, battle slots, and the battle item"
	)
	var previous_data := run.to_dictionary()
	previous_data["save_version"] = GameRun.PREVIOUS_SAVE_VERSION
	var previous_actor: Dictionary = previous_data["party"]["members"][0]
	previous_actor["skill_ids"] = previous_actor["learned_skill_ids"]
	previous_actor.erase("learned_skill_ids")
	previous_actor.erase("battle_skill_ids")
	previous_actor.erase("battle_item_id")
	var previous_migrated := GameRun.from_dictionary(previous_data, database)
	_expect(
		previous_migrated != null
		and previous_migrated.party.leader().learned_skill_ids.size() == 2
		and previous_migrated.party.leader().battle_skill_ids[0] == &"skill.roadside.wind_edge"
		and previous_migrated.party.leader().battle_item_id == medicine.id,
		"v5 should migrate skill_ids and the first usable inventory item into v6 loadout state"
	)
	var legacy_data := run.to_dictionary()
	legacy_data["save_version"] = GameRun.TWO_DIMENSIONAL_SAVE_VERSION
	legacy_data["location"]["position"] = [24.0, 96.0]
	legacy_data["location"]["spawn_id"] = ""
	var migrated := GameRun.from_dictionary(legacy_data)
	_expect(
		migrated != null
		and migrated.location.position == Vector3.ZERO
		and not migrated.location.has_exact_position
		and migrated.location.migrated_from_2d_position,
		"version 3 exact 2D positions should fall back to a semantic spawn"
	)
	_expect(
		restored.randomness.draw_count == 1
		and restored.randomness.roll_percent(50) == run.randomness.roll_percent(50),
		"seeded random progress should round-trip"
	)


func _test_save_service() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	database.build_index()
	var service := SaveService.new()
	service.configure(database)
	service.configure_slots_directory(TEST_SLOTS)
	var run := GameRun.new_game(database)
	run.location.map_id = &"map.roadside.shop"
	_expect(service.save_run(run, TEST_SAVE) == OK, "SaveService should save original content")
	var restored := service.load_run(TEST_SAVE)
	_expect(
		restored != null and restored.location.map_id == &"map.roadside.shop",
		"SaveService should restore the roadside map"
	)
	run.economy.money = 77
	run.flags.set_value(&"flag.test.legacy", true)
	run.world.complete(&"map.roadside.shop", &"entity.test.completed")
	var legacy_data := run.to_dictionary()
	legacy_data["save_version"] = GameRun.TWO_DIMENSIONAL_SAVE_VERSION
	legacy_data["location"] = {
		"map_id": "map.roadside.shop",
		"spawn_id": "",
		"position": [240.0, 120.0],
		"direction": "east",
		"has_exact_position": true,
	}
	var legacy_file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	_expect(legacy_file != null, "save migration test should write a version 3 fixture")
	if legacy_file != null:
		legacy_file.store_string(JSON.stringify(legacy_data))
		legacy_file.close()
	var migrated := service.load_run(TEST_SAVE)
	_expect(
		migrated != null
		and not migrated.location.has_exact_position
		and migrated.location.spawn_id == &"default"
		and migrated.economy.money == 77
		and migrated.flags.is_set(&"flag.test.legacy")
		and migrated.world.is_completed(
			&"map.roadside.shop", &"entity.test.completed"
		),
		"version 3 saves should preserve progress while falling back to a semantic spawn"
	)
	_expect(service.save_slot(run, 1) == OK, "formal slot should save")
	var summary := service.slot_summary(1)
	_expect(
		summary.get("map_name") == "斜坡小铺" and summary.get("leader_name") == "旅人",
		"slot summary should use new original display names"
	)
	_remove_if_exists(TEST_SAVE)
	_remove_if_exists(service.slot_path(1))
	_remove_directory_if_empty(TEST_SLOTS)
	service.free()


func _test_save_baseline_fixtures() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	database.build_index()
	for path: String in [
		"res://tests/fixtures/save_baselines/new_game_v3.json",
		"res://tests/fixtures/save_baselines/gathering_completed_v3.json",
		"res://tests/fixtures/save_baselines/new_game_v6.json",
		"res://tests/fixtures/save_baselines/lantern_foundation_v6.json",
	]:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var run := (
			GameRun.from_dictionary(parsed, database)
			if parsed is Dictionary
			else null
		)
		_expect(
			run != null and database.validate_game_run(run).is_empty(),
			"save baseline should load and validate: %s" % path
		)
	var configured_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/save_baselines/lantern_foundation_v6.json"
	))
	var configured := GameRun.from_dictionary(configured_data, database)
	_expect(
		configured != null
		and configured.party.leader().foundation_id == &"foundation.sharp_metal"
		and configured.party.leader().battle_skill_ids[2]
		== &"skill.roadside.origin_sword_array"
		and configured.party.leader().battle_item_id == &"item.roadside.wound_powder",
		"the v6 configured baseline should preserve foundation equipment and loadout state"
	)


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_directory_if_empty(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
