class_name ContentFactoryTestSuite
extends RefCounted

const POTION_ICON := "res://assets/original/ui/actions/potion.svg"
const SKILL_ICON := "res://assets/original/ui/actions/flying_sword.svg"

var _failures: PackedStringArray = []


func run() -> PackedStringArray:
	_test_progression_creation()
	_test_item_and_equipment_creation()
	_test_skill_and_status_creation()
	_test_battle_content_creation()
	_test_world_creation()
	_test_narrative_creation()
	_test_definition_factory_routing()
	return _failures


func _test_progression_creation() -> void:
	var realm_result := ProgressionDefinitionFactory.create(
		"realm",
		&"realm.test.factory",
		{
			"path": "res://tests/.tmp_factory_realm.tres",
			"max_layer": "3",
			"layer_costs": "10,20",
			"breakthrough_cultivation": "30",
		}
	)
	var realm := realm_result.resource as CultivationRealmDefinition
	_expect(
		realm_result.succeeded()
		and realm != null
		and realm.max_layer == 3
		and realm.layer_cultivation_costs == PackedInt32Array([10, 20])
		and realm.breakthrough_cultivation_required == 30,
		"progression factory should create a realm with exact ordered layer costs"
	)
	var invalid_realm := ProgressionDefinitionFactory.create(
		"realm",
		&"realm.test.invalid_costs",
		{
			"path": "res://tests/.tmp_factory_realm.tres",
			"max_layer": "3",
			"layer_costs": "10",
		}
	)
	_expect(
		not invalid_realm.succeeded()
		and _has_diagnostic(invalid_realm, "realm_layer_cost_count_invalid"),
		"progression factory should reject a realm with incomplete layer costs"
	)
	var foundation_result := ProgressionDefinitionFactory.create(
		"foundation",
		&"foundation.test.factory",
		{
			"realm": "res://content/realms/foundation_establishment.tres",
			"max_hp_bonus": "12",
			"attack_bonus": "3",
		}
	)
	var foundation := foundation_result.resource as DaoFoundationDefinition
	_expect(
		foundation_result.succeeded()
		and foundation != null
		and foundation.required_realm.id == &"realm.foundation_establishment"
		and foundation.max_hp_bonus == 12
		and foundation.attack_bonus == 3,
		"progression factory should bind a foundation to its required realm"
	)
	var actor_result := ProgressionDefinitionFactory.create(
		"actor",
		&"actor.test.factory",
		{
			"realm": "res://content/realms/qi_refining.tres",
			"realm_layer": "9",
			"cultivation_points": "25",
			"foundation": "res://content/foundations/sharp_metal.tres",
			"equipment_slots": "weapon,artifact",
		}
	)
	var actor := actor_result.resource as ActorDefinition
	_expect(
		actor_result.succeeded()
		and actor != null
		and actor.initial_realm.id == &"realm.qi_refining"
		and actor.initial_realm_layer == 9
		and actor.initial_foundation.id == &"foundation.sharp_metal"
		and actor.equipment_slots == [&"weapon", &"artifact"],
		"progression factory should create an actor with validated progression references"
	)


func _test_item_and_equipment_creation() -> void:
	var item_result := ItemSkillDefinitionFactory.create(
		"item",
		&"item.test.factory_heal",
		{
			"path": "res://tests/.tmp_factory_item.tres",
			"icon": POTION_ICON,
			"usable_in_field": "true",
			"effect": "heal",
			"effect_amount": "9",
		}
	)
	var item := item_result.resource as ItemDefinition
	_expect(
		item_result.succeeded()
		and item != null
		and item.id == &"item.test.factory_heal"
		and item.usable_in_field
		and not item.usable_in_battle
		and item.effects.size() == 1
		and item.effects[0] is HealEffect
		and (item.effects[0] as HealEffect).amount == 9,
		"item factory should create a typed usable item with a typed effect"
	)
	var equipment_result := ItemSkillDefinitionFactory.create(
		"equipment",
		&"item.test.invalid_equipment",
		{
			"path": "res://tests/.tmp_factory_equipment.tres",
			"icon": POTION_ICON,
			"usable_in_battle": "true",
		}
	)
	_expect(
		not equipment_result.succeeded()
		and _has_diagnostic(equipment_result, "equipment_usage_unsupported"),
		"equipment factory should reject consumable-only usage options"
	)


func _test_skill_and_status_creation() -> void:
	var skill_result := ItemSkillDefinitionFactory.create(
		"skill",
		&"skill.test.factory_area",
		{
			"path": "res://tests/.tmp_factory_skill.tres",
			"icon": SKILL_ICON,
			"usable_in_battle": "true",
			"target_rule": "area",
			"radius": "2.5",
			"effect": "damage",
			"effect_amount": "11",
		}
	)
	var skill := skill_result.resource as SkillDefinition
	_expect(
		skill_result.succeeded()
		and skill != null
		and skill.target_rule == SkillDefinition.TargetRule.AREA
		and skill.radius == 2.5
		and skill.effects.size() == 1
		and skill.effects[0] is DamageEffect
		and (skill.effects[0] as DamageEffect).amount == 11,
		"skill factory should create a supported battle target and typed damage effect"
	)
	var invalid_skill := ItemSkillDefinitionFactory.create(
		"skill",
		&"skill.test.invalid_field",
		{
			"path": "res://tests/.tmp_factory_skill.tres",
			"icon": SKILL_ICON,
			"usable_in_field": "true",
		}
	)
	_expect(
		not invalid_skill.succeeded()
		and _has_diagnostic(invalid_skill, "skill_field_usage_unsupported"),
		"skill factory should reject unsupported field execution"
	)
	var status_result := ItemSkillDefinitionFactory.create(
		"status",
		&"status.test.factory_burn",
		{
			"duration_seconds": "3.5",
			"tick_interval_seconds": "0.5",
			"periodic_damage": "4",
		}
	)
	var status := status_result.resource as StatusDefinition
	_expect(
		status_result.succeeded()
		and status != null
		and status.duration_seconds == 3.5
		and status.tick_interval_seconds == 0.5
		and status.periodic_damage == 4,
		"status factory should preserve typed timing and damage values"
	)


func _test_battle_content_creation() -> void:
	var enemy_result := BattleContentDefinitionFactory.create(
		"enemy",
		&"enemy.test.factory",
		{
			"path": "res://tests/.tmp_factory_enemy.tres",
			"scene": "res://game/roadside/action_combat_3d/characters/qi_beast_3d.tscn",
			"combat_style": "melee",
			"is_boss": "true",
			"drop_item": "res://content/items/wound_powder.tres",
			"drop_quantity": "2",
		}
	)
	var enemy := enemy_result.resource as EnemyDefinition
	_expect(
		enemy_result.succeeded()
		and enemy != null
		and enemy.is_boss
		and enemy.combat_style == EnemyDefinition.CombatStyle.MELEE
		and enemy.drop_item != null
		and enemy.drop_quantity == 2
		and enemy.strategy is BasicAttackStrategy,
		"battle content factory should create an enemy with explicit role and drop data"
	)
	var invalid_enemy := BattleContentDefinitionFactory.create(
		"enemy",
		&"enemy.test.invalid_pillar",
		{
			"path": "res://tests/.tmp_factory_enemy.tres",
			"scene": "res://game/roadside/action_combat_3d/characters/qi_beast_3d.tscn",
			"combat_style": "melee",
			"charge_staggers_on_pillar": "true",
		}
	)
	_expect(
		not invalid_enemy.succeeded()
		and _has_diagnostic(invalid_enemy, "enemy_pillar_stagger_style_invalid"),
		"battle content factory should reject pillar mechanics on a non-charger"
	)
	var shop_result := BattleContentDefinitionFactory.create(
		"shop",
		&"shop.test.factory",
		{"item": "res://content/items/wound_powder.tres"}
	)
	var shop := shop_result.resource as ShopDefinition
	_expect(
		shop_result.succeeded()
		and shop != null
		and shop.entries.size() == 1
		and shop.entries[0].item.id == &"item.roadside.wound_powder",
		"battle content factory should create a typed shop entry"
	)
	var encounter_result := BattleContentDefinitionFactory.create(
		"encounter",
		&"encounter.test.factory",
		{
			"enemy": "res://content/enemies/qi_eating_whelp.tres",
			"instance_id": "test_whelp",
			"allows_escape": "false",
			"leash_radius": "18",
			"reward_policy": "allow_partial",
		}
	)
	var encounter := encounter_result.resource as BattleEncounter
	_expect(
		encounter_result.succeeded()
		and encounter != null
		and encounter.enemies.size() == 1
		and encounter.enemies[0].instance_id == &"test_whelp"
		and not encounter.allows_escape
		and encounter.leash_radius == 18.0
		and encounter.reward_policy == RewardPolicy.Value.ALLOW_PARTIAL,
		"battle content factory should create a typed encounter with explicit leash and rewards"
	)


func _test_world_creation() -> void:
	var npc_result := WorldDefinitionFactory.create(
		"npc",
		&"npc.test.factory",
		{
			"scene": "res://tests/fixtures/not_character_body_3d.tscn",
			"display_name": "Factory NPC",
			"description": "Factory NPC description",
		}
	)
	var npc := npc_result.resource as NpcDefinition
	_expect(
		npc_result.succeeded()
		and npc != null
		and npc.id == &"npc.test.factory"
		and npc.display_name == "Factory NPC"
		and npc.field_model_3d != null,
		"world factory should create an NPC from a Node3D scene"
	)
	var invalid_npc := WorldDefinitionFactory.create(
		"npc",
		&"npc.test.invalid_scene",
		{"scene": "res://tests/map_generation/map_generation_3d_target_fixture.tscn"}
	)
	_expect(
		not invalid_npc.succeeded()
		and _has_diagnostic(invalid_npc, "npc_scene_type_invalid"),
		"world factory should reject an NPC scene whose root is not Node3D"
	)
	var map_result := WorldDefinitionFactory.create(
		"map",
		&"map.test.factory",
		{
			"scene": "res://tests/map_generation/map_generation_3d_target_fixture.tscn",
			"description": "Factory map description",
			"story": "res://game/roadside/stories/gathering.tres",
		}
	)
	var map_definition := map_result.resource as MapDefinition
	_expect(
		map_result.succeeded()
		and map_definition != null
		and map_definition.default_spawn_id == &"default"
		and map_definition.description == "Factory map description"
		and map_definition.scene != null
		and map_definition.story_module is RoadsideGatheringStory,
		"world factory should create a map with schema defaults, metadata, and a StoryModule"
	)
	var invalid_map := WorldDefinitionFactory.create(
		"map",
		&"map.test.invalid_spawn",
		{
			"scene": "res://tests/map_generation/map_generation_3d_target_fixture.tscn",
			"default_spawn": "missing",
		}
	)
	_expect(
		not invalid_map.succeeded()
		and _has_diagnostic(invalid_map, "map_default_spawn_invalid"),
		"world factory should reject a map whose default spawn is absent"
	)


func _test_narrative_creation() -> void:
	var dialogue_result := NarrativeDefinitionFactory.create(
		"dialogue",
		&"dialogue.test.factory",
		{
			"block": "intro",
			"speaker": "Traveler",
			"text": "The road continues.",
		}
	)
	var dialogue := dialogue_result.resource as DialogueDefinition
	var intro := dialogue.block(&"intro") if dialogue != null else null
	_expect(
		dialogue_result.succeeded()
		and dialogue != null
		and intro != null
		and intro.entries.size() == 1
		and intro.entries[0].speaker == "Traveler"
		and intro.entries[0].text == "The road continues.",
		"narrative factory should create a named dialogue block with its first entry"
	)
	var story_result := NarrativeDefinitionFactory.create(
		"story",
		&"story.test.factory",
		{
			"initial_stage": "accepted",
			"stages": "not_started, accepted, completed",
			"dialogue": "res://game/roadside/stories/gathering_dialogue.tres",
		}
	)
	var story := story_result.resource as StoryModule
	_expect(
		story_result.succeeded()
		and story != null
		and story.initial_stage == &"accepted"
		and story.valid_stages == [&"not_started", &"accepted", &"completed"]
		and story.dialogue != null,
		"narrative factory should create a story with ordered stages and dialogue"
	)
	var invalid_story := NarrativeDefinitionFactory.create(
		"story",
		&"story.test.invalid_stage",
		{
			"path": "res://tests/.tmp_factory_story.tres",
			"initial_stage": "accepted",
			"stages": "not_started,completed",
		}
	)
	_expect(
		not invalid_story.succeeded()
		and _has_diagnostic(invalid_story, "story_initial_stage_invalid"),
		"narrative factory should reject an initial stage outside valid_stages"
	)


func _test_definition_factory_routing() -> void:
	var routed_result := ContentDefinitionFactory.create(
		"status",
		&"status.test.routed",
		{
			"duration_seconds": "2.5",
			"periodic_damage": "3",
		}
	)
	var routed_status := routed_result.resource as StatusDefinition
	_expect(
		routed_result.succeeded()
		and routed_status != null
		and routed_status.id == &"status.test.routed"
		and routed_status.duration_seconds == 2.5
		and routed_status.periodic_damage == 3,
		"definition factory should route supported content to its typed factory"
	)
	var unsupported := ContentDefinitionFactory.create(
		"quest",
		&"quest.test.unsupported",
		{}
	)
	_expect(
		not unsupported.succeeded()
		and _has_diagnostic(unsupported, "content_type_unsupported"),
		"definition factory should report an unsupported content type"
	)


func _has_diagnostic(result: ContentCreationResult, code: String) -> bool:
	for diagnostic: Dictionary in result.diagnostics:
		if diagnostic.get("code") == code:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
