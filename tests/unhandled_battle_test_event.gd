class_name UnhandledBattleTestEvent
extends StoryEvent

var encounter: BattleEncounter


func run(_trigger_id: StringName, story: StoryContext) -> void:
	await story.start_battle(encounter)
