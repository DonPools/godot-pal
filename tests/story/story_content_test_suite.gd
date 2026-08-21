class_name StoryContentTestSuite
extends RefCounted

var _scene_tree: SceneTree
var _failures: PackedStringArray = []


func run(scene_tree: SceneTree) -> PackedStringArray:
	_scene_tree = scene_tree
	await _test_dialogue_options()
	await _test_gathering_story()
	await _test_north_slope_pack_story()
	await _test_lantern_pass_story()
	await _test_battle_trigger_event()
	return _failures


func _test_dialogue_options() -> void:
	var dialogue := load("res://game/roadside/stories/gathering_dialogue.tres") as DialogueDefinition
	_expect(dialogue.validate().is_empty(), "gathering dialogue options should validate")
	var invalid := dialogue.duplicate(true) as DialogueDefinition
	var duplicate_option := invalid.block(&"route_choice").options[0].duplicate(true) as DialogueOption
	invalid.block(&"route_choice").options.append(duplicate_option)
	_expect(
		not invalid.validate().is_empty(),
		"dialogue validation should reject repeated semantic option IDs"
	)
	var dock := ContentDatabaseDock.new()
	_expect(
		dock.dialogue_preview_text(dialogue).contains("[safe_route] 走旧石路"),
		"Dialogue Editor preview should expose semantic option IDs"
	)
	dock.free()
	var layer := (load("res://framework/presentation/dialogue/dialogue_layer.tscn") as PackedScene).instantiate() as DialogueLayer
	_scene_tree.root.add_child(layer)
	_expect(layer.size == Vector2(640, 360), "dialogue overlay should fill the 640x360 viewport")
	_expect(
		layer.text_label.get_theme_font_size(&"font_size") == 22,
		"dialogue text should use the compact native-resolution reading size"
	)
	var holder: Dictionary = {}
	_capture_dialogue_result(layer, dialogue, &"route_choice", holder)
	await _scene_tree.process_frame
	_expect(
		layer.is_typing()
		and not layer.wait_icon.visible
		and layer.text_label.visible_characters < layer.text_label.text.length(),
		"dialogue should type text before exposing its continue marker"
	)
	var advance := InputEventAction.new()
	advance.action = &"interact"
	advance.pressed = true
	layer._unhandled_input(advance)
	await _scene_tree.process_frame
	_expect(
		not layer.is_typing()
		and layer.wait_icon.visible
		and not layer.is_waiting_for_option()
		and layer.text_label.visible_characters == -1,
		"the first advance input should complete the current sentence without advancing"
	)
	layer._unhandled_input(advance)
	await _scene_tree.process_frame
	_expect(layer.is_waiting_for_option(), "dialogue should wait for a typed option")
	_expect(
		layer.option_container is VBoxContainer
		and layer.option_container.get_child_count() == 2,
		"dialogue choices should use two vertically stacked paper tabs"
	)
	var first_option := layer.option_container.get_child(0) as Button
	_expect(
		first_option != null
		and first_option.get_theme_font_size(&"font_size") == 18
		and first_option.has_focus(),
		"the first dialogue choice should expose the native-size focused style"
	)
	layer.option_selected.emit(&"safe_route")
	await _scene_tree.process_frame
	var result := holder.get("result") as DialogueResult
	_expect(
		result != null and result.selected_option_id == &"safe_route",
		"dialogue should return the selected semantic option ID"
	)
	layer.queue_free()
	await _scene_tree.process_frame


func _test_gathering_story() -> void:
	var story := load("res://game/roadside/stories/gathering.tres") as RoadsideGatheringStory
	var fake := FakeStoryContext.new()
	fake.dialogue_choices[&"first_offer"] = &"accept"
	fake.dialogue_choices[&"route_choice"] = &"safe_route"
	await story.run(RoadsideGatheringStory.TALK_SHOPKEEPER, fake)
	_expect(fake.stage == &"trip_one_midday", "safe route should arrive at midday")
	_expect(
		fake.recorded_pending_map_id == story.safe_herb_slope_destination.map_id
		and fake.recorded_pending_spawn_id == story.safe_herb_slope_destination.spawn_id,
		"safe route should travel to the matching slope spawn"
	)

	fake.dialogue_choices[&"harvest_choice"] = &"leave_root"
	await story.run(RoadsideGatheringStory.HARVEST_WEST, fake)
	_expect(fake.stage == &"trip_one_dusk", "first harvest should consume one time segment")
	_expect(fake.inventory_quantities.get(story.herb.id, 0) == 1, "leave-root harvest should give one herb")
	_expect(not fake.source_completed, "leave-root harvest should not permanently complete its source")
	fake.source_completed = false
	await story.run(RoadsideGatheringStory.HARVEST_CENTRE, fake)
	_expect(fake.stage == &"trip_one_late", "two safe-route harvests should return late")
	_expect(fake.inventory_quantities.get(story.herb.id, 0) == 2, "two leave-root patches should fill the delivery")

	await story.run(RoadsideGatheringStory.TALK_SHOPKEEPER, fake)
	_expect(fake.stage == &"between_trips", "first delivery should open the repeat trip")
	_expect(
		fake.delivered_items.size() == 1
		and fake.delivered_items[0].get("money_reward") == 6,
		"late first delivery should atomically pay half wages"
	)

	fake.dialogue_choices[&"second_offer"] = &"accept"
	fake.dialogue_choices[&"route_choice"] = &"shortcut"
	fake.chance_results.append(true)
	await story.run(RoadsideGatheringStory.TALK_SHOPKEEPER, fake)
	_expect(fake.stage == &"trip_two_early", "successful shortcut should preserve the early segment")
	_expect(fake.is_flag_set(RoadsideGatheringStory.SECOND_TRIP_STARTED), "second trip should be persisted")

	fake.source_completed = false
	fake.dialogue_choices[&"harvest_choice"] = &"leave_root"
	await story.run(RoadsideGatheringStory.HARVEST_WEST, fake)
	fake.source_completed = false
	fake.dialogue_choices[&"harvest_choice"] = &"uproot"
	await story.run(RoadsideGatheringStory.HARVEST_CENTRE, fake)
	_expect(fake.source_completed, "uprooting should permanently complete only the current source")
	_expect(fake.is_flag_set(RoadsideGatheringStory.UPROOTED_CENTRE), "uproot choice should persist")
	await story.run(RoadsideGatheringStory.TALK_SHOPKEEPER, fake)
	_expect(fake.stage == &"completed", "second delivery should complete the two-trip slice")
	_expect(
		fake.delivered_items.size() == 2
		and fake.delivered_items[1].get("money_reward") == 12,
		"on-time second delivery should pay full wages"
	)
	_expect(&"final_mixed" in fake.shown_blocks, "mixed harvesting should produce a concrete final observation")

	var slipped := FakeStoryContext.new()
	slipped.stage = &"between_trips"
	slipped.dialogue_choices[&"second_offer"] = &"accept"
	slipped.dialogue_choices[&"route_choice"] = &"shortcut"
	slipped.chance_results.append(false)
	await story.run(RoadsideGatheringStory.TALK_SHOPKEEPER, slipped)
	_expect(slipped.stage == &"trip_two_dusk", "failed shortcut should consume two time segments")
	_expect(&"shortcut_slip" in slipped.shown_blocks, "shortcut risk should be visible to the player")


func _test_north_slope_pack_story() -> void:
	var story := load(
		"res://game/roadside/action_combat_3d/stories/north_slope_pack.tres"
	) as NorthSlopePackStory
	var victory := FakeStoryContext.new()
	victory.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await story.run(NorthSlopePackStory.CONFRONT, victory)
	_expect(
		victory.inventory_quantities.get(story.supply_item.id, 0) == 2
		and victory.is_flag_set(NorthSlopePackStory.SUPPLY_GRANTED),
		"the first pack confrontation should grant exactly two battle supplies"
	)
	_expect(
		victory.source_completed
		and victory.stage == &"cleared"
		and &"victory" in victory.shown_blocks,
		"Victory should complete the source, advance stage, and show its result"
	)
	var escaped := FakeStoryContext.new()
	escaped.flags[NorthSlopePackStory.SUPPLY_GRANTED] = true
	escaped.next_battle_result.outcome = BattleResult.Outcome.ESCAPED
	await story.run(NorthSlopePackStory.CONFRONT, escaped)
	_expect(
		not escaped.source_completed
		and escaped.stage == &"not_started"
		and escaped.inventory_quantities.is_empty()
		and &"escaped" in escaped.shown_blocks,
		"Escaped should retain the encounter without duplicating its supply"
	)
	var defeated := FakeStoryContext.new()
	defeated.next_battle_result.outcome = BattleResult.Outcome.DEFEAT
	await story.run(NorthSlopePackStory.CONFRONT, defeated)
	_expect(
		defeated.party_restored
		and defeated.recorded_pending_map_id == story.defeat_destination.map_id
		and defeated.recorded_pending_spawn_id == story.defeat_destination.spawn_id
		and not defeated.source_completed,
		"Defeat should restore the party and terminal travel to the safe spawn"
	)


func _test_lantern_pass_story() -> void:
	var story := load(
		"res://game/roadside/action_combat_3d/stories/lantern_pass.tres"
	) as LanternPassStory
	_expect(story != null, "lantern pass story should load")
	var first := FakeStoryContext.new()
	first.stage = &"not_started"
	first.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await story.run(LanternPassStory.FIGHT_FIRST, first)
	_expect(
		first.source_completed and first.stage == &"first_cleared",
		"the first lantern pack should complete its source and advance stage"
	)
	var escaped := FakeStoryContext.new()
	escaped.stage = &"first_cleared"
	escaped.next_battle_result.outcome = BattleResult.Outcome.ESCAPED
	await story.run(LanternPassStory.FIGHT_SECOND, escaped)
	_expect(
		not escaped.source_completed
		and escaped.stage == &"first_cleared"
		and &"escaped" in escaped.shown_blocks,
		"an escaped lantern encounter should retain its source and stage"
	)
	var defeated := FakeStoryContext.new()
	defeated.stage = &"second_cleared"
	defeated.next_battle_result.outcome = BattleResult.Outcome.DEFEAT
	await story.run(LanternPassStory.FIGHT_THIRD, defeated)
	_expect(
		defeated.party_restored
		and defeated.recorded_pending_map_id == story.defeat_destination.map_id
		and defeated.recorded_pending_spawn_id == story.defeat_destination.spawn_id,
		"lantern defeat should restore the party and terminal travel to the safe spawn"
	)
	var elite := FakeStoryContext.new()
	elite.stage = &"third_cleared"
	elite.dialogue_choices[&"gear_choice"] = &"sword_seal"
	elite.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await story.run(LanternPassStory.FIGHT_ELITE, elite)
	_expect(
		elite.source_completed
		and elite.stage == &"elite_cleared"
		and elite.inventory_quantities.get(story.suppressing_sword_seal.id, 0) == 1,
		"elite Victory should atomically grant the selected build item before advancing"
	)
	var boss := FakeStoryContext.new()
	boss.stage = &"elite_cleared"
	boss.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await story.run(LanternPassStory.CONFRONT_BEAST, boss)
	_expect(
		boss.source_completed
		and boss.stage == &"boss_defeated"
		and boss.inventory_quantities.get(story.stone_heart.id, 0) == 1,
		"Boss Victory should grant exactly one breakthrough catalyst and complete its source"
	)
	var restored := FakeStoryContext.new()
	restored.stage = &"boss_defeated"
	restored.dialogue_choices[&"array_choice"] = &"restore"
	await story.run(LanternPassStory.RESOLVE_ARRAY, restored)
	_expect(
		restored.source_completed
		and restored.stage == &"restored"
		and restored.is_flag_set(LanternPassStory.ARRAY_RESTORED)
		and restored.played_sound_paths.has(story.array_restore_sound.resource_path)
		and restored.inventory_quantities.is_empty(),
		"restoring the array should open the public route without granting the core item"
	)
	var salvaged := FakeStoryContext.new()
	salvaged.stage = &"boss_defeated"
	salvaged.dialogue_choices[&"array_choice"] = &"salvage"
	await story.run(LanternPassStory.RESOLVE_ARRAY, salvaged)
	_expect(
		salvaged.source_completed
		and salvaged.stage == &"salvaged"
		and salvaged.is_flag_set(LanternPassStory.ARRAY_SALVAGED)
		and salvaged.played_sound_paths.has(story.array_salvage_sound.resource_path)
		and salvaged.inventory_quantities.get(story.lantern_core_fragment.id, 0) == 1,
		"salvaging the array should grant the core equipment before persisting the dark result"
	)
	var not_ready := FakeStoryContext.new()
	not_ready.stage = &"restored"
	not_ready.breakthrough_ready = false
	await story.run(LanternPassStory.ATTEMPT_BREAKTHROUGH, not_ready)
	_expect(
		not not_ready.source_completed
		and &"cultivation_not_ready" in not_ready.shown_blocks,
		"the altar should reject breakthrough before cultivation is full"
	)
	var breakthrough := FakeStoryContext.new()
	breakthrough.stage = &"restored"
	breakthrough.inventory_quantities[story.stone_heart.id] = 1
	breakthrough.dialogue_choices[&"foundation_choice"] = &"flowing_water"
	await story.run(LanternPassStory.ATTEMPT_BREAKTHROUGH, breakthrough)
	_expect(
		breakthrough.source_completed
		and breakthrough.stage == &"foundation_established"
		and breakthrough.recorded_foundation_id == story.flowing_water_foundation.id
		and breakthrough.recorded_catalyst_id == story.stone_heart.id
		and breakthrough.played_sound_paths.has(story.breakthrough_sound.resource_path)
		and breakthrough.inventory_quantities.get(story.stone_heart.id, 0) == 0,
		"a valid foundation choice should consume the catalyst and atomically establish the foundation"
	)
	var final_test := FakeStoryContext.new()
	final_test.stage = &"foundation_established"
	final_test.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await story.run(LanternPassStory.FINAL_TEST, final_test)
	_expect(
		final_test.source_completed and final_test.stage == &"mvp_complete",
		"the post-breakthrough pack should finish the MVP exactly once"
	)


func _test_battle_trigger_event() -> void:
	var encounter := TestContentFixtures.encounter()
	var event := BattleTriggerEvent.new()
	event.encounter = encounter
	var victory := FakeStoryContext.new()
	victory.next_battle_result.outcome = BattleResult.Outcome.VICTORY
	await event.run(&"default", victory)
	_expect(victory.source_completed, "Victory should complete a BattleTriggerEvent source")
	var escaped := FakeStoryContext.new()
	escaped.next_battle_result.outcome = BattleResult.Outcome.ESCAPED
	await event.run(&"default", escaped)
	_expect(
		not escaped.source_completed and not escaped.party_restored,
		"Escaped should preserve the source without restoring the party"
	)
	event.defeat_destination = MapDestination.create(&"map.test.safe", &"safe")
	var defeated := FakeStoryContext.new()
	defeated.next_battle_result.outcome = BattleResult.Outcome.DEFEAT
	await event.run(&"default", defeated)
	_expect(
		defeated.party_restored
		and defeated.recorded_pending_map_id == &"map.test.safe"
		and defeated.recorded_pending_spawn_id == &"safe",
		"Defeat should restore the party and register terminal travel"
	)


func _capture_dialogue_result(
	layer: DialogueLayer,
	dialogue: DialogueDefinition,
	block_id: StringName,
	holder: Dictionary
) -> void:
	holder["result"] = await layer.show_dialogue(dialogue, block_id)




func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
