class_name TestContentFixtures
extends RefCounted


static func encounter() -> BattleEncounter:
	var enemy := EnemyDefinition.new()
	enemy.id = &"enemy.test.map_melee"
	enemy.display_name = "Map Test Enemy"
	enemy.max_hp = 10
	enemy.attack = 5
	var entry := EncounterEnemy.new()
	entry.enemy = enemy
	entry.instance_id = &"enemy.test.map_01"
	var encounter := BattleEncounter.new()
	encounter.id = &"encounter.test.map_local"
	encounter.display_name = "Map Test Encounter"
	encounter.enemies.append(entry)
	return encounter
