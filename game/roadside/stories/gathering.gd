@tool
class_name RoadsideGatheringStory
extends StoryModule

const TALK_SHOPKEEPER := &"talk_shopkeeper"
const ENTER_SLOPE := &"enter_herb_slope"
const HARVEST_WEST := &"harvest_west"
const HARVEST_CENTRE := &"harvest_centre"
const HARVEST_EAST := &"harvest_east"

const ACCEPT := &"accept"
const LATER := &"later"
const SAFE_ROUTE := &"safe_route"
const SHORTCUT := &"shortcut"
const LEAVE_ROOT := &"leave_root"
const UPROOT := &"uproot"

const SECOND_TRIP_STARTED := &"flag.story.roadside.gathering.second_trip_started"
const ENTERED_TRIP_ONE := &"flag.story.roadside.gathering.entered.trip_one"
const ENTERED_TRIP_TWO := &"flag.story.roadside.gathering.entered.trip_two"

const FIRST_WEST := &"flag.story.roadside.gathering.harvested.trip_one.west"
const FIRST_CENTRE := &"flag.story.roadside.gathering.harvested.trip_one.centre"
const FIRST_EAST := &"flag.story.roadside.gathering.harvested.trip_one.east"
const SECOND_WEST := &"flag.story.roadside.gathering.harvested.trip_two.west"
const SECOND_CENTRE := &"flag.story.roadside.gathering.harvested.trip_two.centre"
const SECOND_EAST := &"flag.story.roadside.gathering.harvested.trip_two.east"

const UPROOTED_WEST := &"flag.story.roadside.gathering.uprooted.west"
const UPROOTED_CENTRE := &"flag.story.roadside.gathering.uprooted.centre"
const UPROOTED_EAST := &"flag.story.roadside.gathering.uprooted.east"

@export var herb: ItemDefinition
@export var herb_slope: MapDefinition
@export_range(1, 12) var delivery_quantity: int = 2
@export_range(0, 999) var on_time_payment: int = 12
@export_range(0, 999) var late_payment: int = 6
@export_range(0, 100) var shortcut_success_chance: int = 50


func get_trigger_ids() -> Array[StringName]:
	return [
		TALK_SHOPKEEPER,
		ENTER_SLOPE,
		HARVEST_WEST,
		HARVEST_CENTRE,
		HARVEST_EAST,
	]


func can_run(trigger_id: StringName, story: StoryContext) -> bool:
	if trigger_id in [TALK_SHOPKEEPER, ENTER_SLOPE]:
		return true
	var trip := _trip_number(story.get_stage(self))
	if trip == 0 or story.is_source_entity_completed():
		return false
	return not story.is_flag_set(_harvested_flag(trigger_id, trip))


func get_objective_text(stage_id: StringName, map_id: StringName) -> String:
	if stage_id == &"not_started":
		return "询问店主 · 北坡新生返青草"
	if stage_id == &"between_trips":
		return "歇过一夜 · 再问店主"
	if stage_id == &"completed":
		return "两趟采药已毕 · 山坡留痕"
	if _trip_number(stage_id) > 0:
		if map_id == &"map.roadside.herb_slope":
			return "采足两份返青草 · %s" % _time_label(stage_id)
		return "把返青草交给店主 · %s" % _time_label(stage_id)
	return ""


func run(trigger_id: StringName, story: StoryContext) -> void:
	match trigger_id:
		TALK_SHOPKEEPER:
			await _talk_shopkeeper(story)
		ENTER_SLOPE:
			await _enter_slope(story)
		HARVEST_WEST, HARVEST_CENTRE, HARVEST_EAST:
			await _harvest(trigger_id, story)


func _talk_shopkeeper(story: StoryContext) -> void:
	var stage := story.get_stage(self)
	match stage:
		&"not_started":
			var offer: DialogueResult = await story.show_dialogue(dialogue, &"first_offer")
			if offer.selected_option_id == ACCEPT:
				await _choose_route(story, 1)
			else:
				await story.show_dialogue(dialogue, &"offer_later")
		&"between_trips":
			var offer: DialogueResult = await story.show_dialogue(dialogue, &"second_offer")
			if offer.selected_option_id == ACCEPT:
				story.set_flag(SECOND_TRIP_STARTED)
				await _choose_route(story, 2)
			else:
				await story.show_dialogue(dialogue, &"offer_later")
		&"completed":
			await story.show_dialogue(dialogue, _final_block(story))
		_:
			if _trip_number(stage) > 0:
				await _settle_or_return(story)


func _choose_route(story: StoryContext, trip: int) -> void:
	var choice: DialogueResult = await story.show_dialogue(dialogue, &"route_choice")
	if choice.selected_option_id == SAFE_ROUTE:
		_set_trip_time(story, trip, 1)
		await story.show_dialogue(dialogue, &"safe_departure")
		story.travel_to(herb_slope, &"safe_entry")
		return
	if choice.selected_option_id != SHORTCUT:
		return
	if story.roll_percent(shortcut_success_chance):
		_set_trip_time(story, trip, 0)
		await story.show_dialogue(dialogue, &"shortcut_clear")
	else:
		_set_trip_time(story, trip, 2)
		await story.show_dialogue(dialogue, &"shortcut_slip")
	story.travel_to(herb_slope, &"shortcut_entry")
	return


func _enter_slope(story: StoryContext) -> void:
	var stage := story.get_stage(self)
	var trip := _trip_number(stage)
	if trip == 0:
		return
	var entered_flag := ENTERED_TRIP_ONE if trip == 1 else ENTERED_TRIP_TWO
	if story.is_flag_set(entered_flag):
		return
	story.set_flag(entered_flag)
	await story.show_dialogue(dialogue, &"slope_arrival")


func _harvest(trigger_id: StringName, story: StoryContext) -> void:
	var trip := _trip_number(story.get_stage(self))
	if trip == 0:
		return
	var choice: DialogueResult = await story.show_dialogue(dialogue, &"harvest_choice")
	if choice.selected_option_id not in [LEAVE_ROOT, UPROOT]:
		return
	var quantity := 1 if choice.selected_option_id == LEAVE_ROOT else 2
	var reward := story.give_item(herb, quantity, RewardPolicy.Value.ALL_OR_NOTHING)
	if not reward.succeeded():
		await story.show_dialogue(dialogue, &"basket_full")
		return
	story.set_flag(_harvested_flag(trigger_id, trip))
	if choice.selected_option_id == UPROOT:
		story.set_flag(_uprooted_flag(trigger_id))
		story.complete_source_entity()
	await story.show_dialogue(
		dialogue,
		&"harvest_left_root" if choice.selected_option_id == LEAVE_ROOT else &"harvest_uprooted"
	)
	_advance_time(story, trip)


func _settle_or_return(story: StoryContext) -> void:
	var stage := story.get_stage(self)
	var trip := _trip_number(stage)
	if story.item_quantity(herb) < delivery_quantity:
		await story.show_dialogue(dialogue, &"not_enough")
		story.travel_to(herb_slope, &"safe_entry")
		return
	var payment := late_payment if _time_index(stage) >= 3 else on_time_payment
	var delivery := story.deliver_items(herb, delivery_quantity, payment)
	if not delivery.completed():
		await story.show_dialogue(dialogue, &"not_enough")
		return
	await story.show_dialogue(
		dialogue,
		&"delivery_late" if _time_index(stage) >= 3 else &"delivery_on_time"
	)
	if trip == 1:
		story.set_stage(self, &"between_trips")
		await story.show_dialogue(dialogue, &"night_passes")
	else:
		story.set_stage(self, &"completed")
		await story.show_dialogue(dialogue, _final_block(story))


func _advance_time(story: StoryContext, trip: int) -> void:
	var next_time := mini(_time_index(story.get_stage(self)) + 1, 3)
	_set_trip_time(story, trip, next_time)


func _set_trip_time(story: StoryContext, trip: int, time_index: int) -> void:
	var stage: StringName
	if trip == 1:
		stage = [&"trip_one_early", &"trip_one_midday", &"trip_one_dusk", &"trip_one_late"][time_index]
	else:
		stage = [&"trip_two_early", &"trip_two_midday", &"trip_two_dusk", &"trip_two_late"][time_index]
	story.set_stage(self, stage)


func _trip_number(stage: StringName) -> int:
	if String(stage).begins_with("trip_one_"):
		return 1
	if String(stage).begins_with("trip_two_"):
		return 2
	return 0


func _time_index(stage: StringName) -> int:
	if String(stage).ends_with("_early"):
		return 0
	if String(stage).ends_with("_midday"):
		return 1
	if String(stage).ends_with("_dusk"):
		return 2
	return 3


func _time_label(stage: StringName) -> String:
	return ["日头尚早", "已近正午", "日头西斜", "已经入夜"][_time_index(stage)]


func _harvested_flag(trigger_id: StringName, trip: int) -> StringName:
	match trigger_id:
		HARVEST_WEST:
			return FIRST_WEST if trip == 1 else SECOND_WEST
		HARVEST_CENTRE:
			return FIRST_CENTRE if trip == 1 else SECOND_CENTRE
		HARVEST_EAST:
			return FIRST_EAST if trip == 1 else SECOND_EAST
	return &""


func _uprooted_flag(trigger_id: StringName) -> StringName:
	match trigger_id:
		HARVEST_WEST:
			return UPROOTED_WEST
		HARVEST_CENTRE:
			return UPROOTED_CENTRE
		HARVEST_EAST:
			return UPROOTED_EAST
	return &""


func _final_block(story: StoryContext) -> StringName:
	var uprooted_count := 0
	for flag_id: StringName in [UPROOTED_WEST, UPROOTED_CENTRE, UPROOTED_EAST]:
		if story.is_flag_set(flag_id):
			uprooted_count += 1
	if uprooted_count == 0:
		return &"final_regrowth"
	if uprooted_count >= 2:
		return &"final_depleted"
	return &"final_mixed"
