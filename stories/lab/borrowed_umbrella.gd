class_name BorrowedUmbrellaStory
extends StoryModule

const ENTER_HALL := &"enter_hall"
const TALK_INNKEEPER := &"talk_innkeeper"
const TALK_GUEST := &"talk_guest"
const ENTER_COURTYARD := &"enter_courtyard"
const TALK_TRAVELER := &"talk_traveler"
const TAKE_UMBRELLA := &"take_umbrella"
const COURTYARD_SEEN := &"flag.story.lab.borrowed_umbrella.courtyard_seen"


func get_trigger_ids() -> Array[StringName]:
	return [
		ENTER_HALL,
		TALK_INNKEEPER,
		TALK_GUEST,
		ENTER_COURTYARD,
		TALK_TRAVELER,
		TAKE_UMBRELLA,
	]


func run(trigger_id: StringName, story: StoryContext) -> void:
	match trigger_id:
		ENTER_HALL:
			await _enter_hall(story)
		TALK_INNKEEPER:
			await _talk_innkeeper(story)
		TALK_GUEST:
			await story.show_dialogue(dialogue, &"quiet_guest")
		ENTER_COURTYARD:
			await _enter_courtyard(story)
		TALK_TRAVELER:
			await _talk_traveler(story)
		TAKE_UMBRELLA:
			await _take_umbrella(story)


func _enter_hall(story: StoryContext) -> void:
	if story.get_stage(self) != &"not_started":
		return
	await story.show_dialogue(dialogue, &"opening")
	story.set_stage(self, &"met_innkeeper")


func _talk_innkeeper(story: StoryContext) -> void:
	match story.get_stage(self):
		&"not_started", &"met_innkeeper":
			await story.show_dialogue(dialogue, &"innkeeper_request")
			story.set_stage(self, &"looking_for_owner")
		&"looking_for_owner":
			await story.show_dialogue(dialogue, &"innkeeper_reminder")
		&"owner_found":
			await story.show_dialogue(dialogue, &"innkeeper_waiting")
		&"umbrella_found":
			await story.show_dialogue(dialogue, &"innkeeper_finish")
			story.set_stage(self, &"completed")
		&"completed":
			await story.show_dialogue(dialogue, &"innkeeper_complete")


func _enter_courtyard(story: StoryContext) -> void:
	if story.get_stage(self) != &"looking_for_owner" or story.is_flag_set(COURTYARD_SEEN):
		return
	await story.show_dialogue(dialogue, &"courtyard_first")
	story.set_flag(COURTYARD_SEEN)


func _talk_traveler(story: StoryContext) -> void:
	match story.get_stage(self):
		&"looking_for_owner":
			await story.show_dialogue(dialogue, &"traveler_reveal")
			story.set_stage(self, &"owner_found")
		&"owner_found":
			await story.show_dialogue(dialogue, &"traveler_repeat")
		&"umbrella_found", &"completed":
			await story.show_dialogue(dialogue, &"traveler_thanks")
		_:
			await story.show_dialogue(dialogue, &"traveler_before")


func _take_umbrella(story: StoryContext) -> void:
	if story.get_stage(self) != &"owner_found":
		await story.show_dialogue(dialogue, &"umbrella_locked")
		return
	await story.show_dialogue(dialogue, &"umbrella_take")
	story.complete_source_entity()
	story.set_stage(self, &"umbrella_found")
