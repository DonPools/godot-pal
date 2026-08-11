extends SceneTree

const DATABASE_PATH := "res://content/content_database.tres"
const STORY_PATH := "res://stories/lab/borrowed_umbrella.tres"

var _json_output: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	_json_output = "--json" in arguments
	if arguments.is_empty() or arguments[0] != "validate":
		_finish(2, ["usage: content_cli.gd -- validate [--json]"])
		return
	var errors := _validate()
	_finish(0 if errors.is_empty() else 1, errors)


func _validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var database := load(DATABASE_PATH) as ContentDatabase
	if database == null:
		errors.append("content database could not be loaded: %s" % DATABASE_PATH)
		return errors
	errors.append_array(database.build_index())
	for required_map: StringName in [&"map.lab.inn_hall", &"map.lab.rain_courtyard"]:
		if not database.has_map(required_map):
			errors.append("required framework-lab map is missing: %s" % required_map)
	var story := load(STORY_PATH) as StoryModule
	if story == null:
		errors.append("story could not be loaded: %s" % STORY_PATH)
		return errors
	if story.id != &"story.lab.borrowed_umbrella":
		errors.append("story has an unexpected id: %s" % story.id)
	if story.initial_stage not in story.valid_stages:
		errors.append("story initial stage is not valid: %s" % story.initial_stage)
	var stages: Dictionary[StringName, bool] = {}
	for stage_id: StringName in story.valid_stages:
		if stage_id.is_empty() or stages.has(stage_id):
			errors.append("story contains an empty or repeated stage: %s" % stage_id)
		stages[stage_id] = true
	var triggers: Dictionary[StringName, bool] = {}
	for trigger_id: StringName in story.get_trigger_ids():
		if trigger_id.is_empty() or triggers.has(trigger_id):
			errors.append("story contains an empty or repeated trigger: %s" % trigger_id)
		triggers[trigger_id] = true
	if story.dialogue == null:
		errors.append("story has no DialogueDefinition")
	else:
		errors.append_array(story.dialogue.validate())
	errors.append_array(MapSceneValidator.new().validate(database, story))
	return errors


func _finish(code: int, errors: PackedStringArray) -> void:
	if _json_output:
		print(JSON.stringify({
			"ok": errors.is_empty(),
			"error_count": errors.size(),
			"errors": Array(errors),
		}))
	else:
		if errors.is_empty():
			print("content validation passed")
		else:
			for error: String in errors:
				printerr(error)
	quit(code)
