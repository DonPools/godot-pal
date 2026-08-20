@tool
class_name LanternPassStory
extends StoryModule

const ARRAY_RESTORED := &"flag.story.roadside.lantern_pass.array_restored"
const ARRAY_SALVAGED := &"flag.story.roadside.lantern_pass.array_salvaged"

const FIGHT_FIRST := &"fight_first_pack"
const FIGHT_SECOND := &"fight_second_pack"
const FIGHT_THIRD := &"fight_third_pack"
const FIGHT_ELITE := &"fight_elite"
const CONFRONT_BEAST := &"confront_beast"
const RESOLVE_ARRAY := &"resolve_array"
const ATTEMPT_BREAKTHROUGH := &"attempt_breakthrough"
const FINAL_TEST := &"final_test"
const TALK_KEEPER := &"talk_keeper"

@export var first_encounter: BattleEncounter
@export var second_encounter: BattleEncounter
@export var third_encounter: BattleEncounter
@export var elite_encounter: BattleEncounter
@export var boss_encounter: BattleEncounter
@export var final_encounter: BattleEncounter
@export var returning_sword_case: EquipmentDefinition
@export var suppressing_sword_seal: EquipmentDefinition
@export var stone_heart: ItemDefinition
@export var lantern_core_fragment: EquipmentDefinition
@export var sharp_metal_foundation: DaoFoundationDefinition
@export var flowing_water_foundation: DaoFoundationDefinition
@export var breakthrough_sound: AudioStream
@export var array_restore_sound: AudioStream
@export var array_salvage_sound: AudioStream
@export var defeat_map: MapDefinition
@export var defeat_spawn_id: StringName = &"from_lantern"


func get_trigger_ids() -> Array[StringName]:
	return [
		FIGHT_FIRST,
		FIGHT_SECOND,
		FIGHT_THIRD,
		FIGHT_ELITE,
		CONFRONT_BEAST,
		RESOLVE_ARRAY,
		ATTEMPT_BREAKTHROUGH,
		FINAL_TEST,
		TALK_KEEPER,
	]


func can_run(trigger_id: StringName, story: StoryContext) -> bool:
	if trigger_id == TALK_KEEPER:
		return true
	if story.is_source_entity_completed():
		return false
	var stage := story.get_stage(self)
	match trigger_id:
		FIGHT_FIRST:
			return stage == &"not_started"
		FIGHT_SECOND:
			return stage == &"first_cleared"
		FIGHT_THIRD:
			return stage == &"second_cleared"
		FIGHT_ELITE:
			return stage == &"third_cleared"
		CONFRONT_BEAST:
			return stage == &"elite_cleared"
		RESOLVE_ARRAY:
			return stage == &"boss_defeated"
		ATTEMPT_BREAKTHROUGH:
			return stage in [&"restored", &"salvaged"]
		FINAL_TEST:
			return stage == &"foundation_established"
	return false


func get_objective_text(stage_id: StringName, map_id: StringName) -> String:
	if map_id != &"map.roadside.lantern_pass":
		return ""
	match stage_id:
		&"not_started":
			return "进入隘口 · 普攻命中回气"
		&"first_cleared", &"second_cleared", &"third_cleared":
			return "沿旧路深入 · 先破远程"
		&"elite_cleared":
			return "调查阵柱 · 引岩兽撞亮柱"
		&"boss_defeated":
			return "阵灯抉择 · 修复或拆取阵芯"
		&"restored", &"salvaged":
			return "携岩心前往筑基坛"
		&"foundation_established":
			return "返回南侧 · 清理灵潮"
		&"mvp_complete":
			return "阵灯已定 · 可回守灯人处"
	return ""


func run(trigger_id: StringName, story: StoryContext) -> void:
	match trigger_id:
		FIGHT_FIRST:
			await _run_standard_encounter(story, first_encounter, &"first_cleared")
		FIGHT_SECOND:
			await _run_standard_encounter(story, second_encounter, &"second_cleared")
		FIGHT_THIRD:
			await _run_standard_encounter(story, third_encounter, &"third_cleared")
		FIGHT_ELITE:
			await _run_elite(story)
		CONFRONT_BEAST:
			await _run_boss(story)
		RESOLVE_ARRAY:
			await _resolve_array(story)
		ATTEMPT_BREAKTHROUGH:
			await _attempt_breakthrough(story)
		FINAL_TEST:
			await _run_standard_encounter(story, final_encounter, &"mvp_complete")
		TALK_KEEPER:
			await _talk_keeper(story)


func _run_standard_encounter(
	story: StoryContext,
	encounter: BattleEncounter,
	next_stage: StringName
) -> void:
	if encounter == null:
		return
	var result := await story.start_battle(encounter)
	match result.outcome:
		BattleResult.Outcome.VICTORY:
			story.complete_source_entity()
			story.set_stage(self, next_stage)
		BattleResult.Outcome.ESCAPED:
			await story.show_dialogue(dialogue, &"escaped")
		BattleResult.Outcome.DEFEAT:
			_handle_defeat(story)


func _run_elite(story: StoryContext) -> void:
	if elite_encounter == null:
		return
	var result := await story.start_battle(elite_encounter)
	match result.outcome:
		BattleResult.Outcome.VICTORY:
			var choice := await story.show_dialogue(dialogue, &"gear_choice")
			var equipment := (
				suppressing_sword_seal
				if choice.selected_option_id == &"sword_seal"
				else returning_sword_case
			)
			if equipment == null:
				return
			var reward := story.give_item(
				equipment,
				1,
				RewardPolicy.Value.ALL_OR_NOTHING
			)
			if reward.succeeded() or story.item_quantity(equipment) > 0:
				story.complete_source_entity()
				story.set_stage(self, &"elite_cleared")
				await story.show_dialogue(dialogue, &"gear_received")
			else:
				await story.show_dialogue(dialogue, &"reward_blocked")
		BattleResult.Outcome.ESCAPED:
			await story.show_dialogue(dialogue, &"escaped")
		BattleResult.Outcome.DEFEAT:
			_handle_defeat(story)


func _run_boss(story: StoryContext) -> void:
	if boss_encounter == null or stone_heart == null:
		return
	var result := await story.start_battle(boss_encounter)
	match result.outcome:
		BattleResult.Outcome.VICTORY:
			var reward := story.give_item(
				stone_heart,
				1,
				RewardPolicy.Value.ALL_OR_NOTHING
			)
			if reward.succeeded() or story.item_quantity(stone_heart) > 0:
				story.complete_source_entity()
				story.set_stage(self, &"boss_defeated")
				await story.show_dialogue(dialogue, &"boss_victory")
			else:
				await story.show_dialogue(dialogue, &"reward_blocked")
		BattleResult.Outcome.ESCAPED:
			await story.show_dialogue(dialogue, &"escaped")
		BattleResult.Outcome.DEFEAT:
			_handle_defeat(story)


func _resolve_array(story: StoryContext) -> void:
	var choice := await story.show_dialogue(dialogue, &"array_choice")
	if choice.selected_option_id == &"salvage":
		if lantern_core_fragment == null:
			return
		var reward := story.give_item(
			lantern_core_fragment,
			1,
			RewardPolicy.Value.ALL_OR_NOTHING
		)
		if not reward.succeeded() and story.item_quantity(lantern_core_fragment) <= 0:
			await story.show_dialogue(dialogue, &"reward_blocked")
			return
		story.set_flag(ARRAY_SALVAGED)
		story.set_stage(self, &"salvaged")
		story.play_sound(array_salvage_sound)
		await story.show_dialogue(dialogue, &"array_salvaged")
	else:
		story.set_flag(ARRAY_RESTORED)
		story.set_stage(self, &"restored")
		story.play_sound(array_restore_sound)
		await story.show_dialogue(dialogue, &"array_restored")
	story.complete_source_entity()


func _attempt_breakthrough(story: StoryContext) -> void:
	if not story.is_ready_for_breakthrough():
		await story.show_dialogue(dialogue, &"cultivation_not_ready")
		return
	if stone_heart == null or story.item_quantity(stone_heart) < 1:
		await story.show_dialogue(dialogue, &"heart_missing")
		return
	var choice := await story.show_dialogue(dialogue, &"foundation_choice")
	var foundation := (
		flowing_water_foundation
		if choice.selected_option_id == &"flowing_water"
		else sharp_metal_foundation
	)
	var result := story.breakthrough(foundation, stone_heart)
	if not result.succeeded():
		await story.show_dialogue(dialogue, &"breakthrough_failed")
		return
	story.play_sound(breakthrough_sound)
	story.complete_source_entity()
	story.set_stage(self, &"foundation_established")
	await story.show_dialogue(dialogue, &"breakthrough_succeeded")


func _talk_keeper(story: StoryContext) -> void:
	match story.get_stage(self):
		&"boss_defeated":
			await story.show_dialogue(dialogue, &"keeper_after_boss")
		&"restored":
			await story.show_dialogue(dialogue, &"keeper_restored")
		&"salvaged":
			await story.show_dialogue(dialogue, &"keeper_salvaged")
		&"foundation_established", &"mvp_complete":
			await story.show_dialogue(dialogue, &"keeper_foundation")
		_:
			await story.show_dialogue(dialogue, &"keeper_intro")


func _handle_defeat(story: StoryContext) -> void:
	story.restore_party()
	if defeat_map != null:
		story.travel_to(defeat_map, defeat_spawn_id)
