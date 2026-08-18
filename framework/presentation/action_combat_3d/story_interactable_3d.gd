class_name StoryInteractable3D
extends Area3D

enum CompletedBehavior {
	NONE,
	HIDE_OWNER,
}

@export var trigger_id: StringName = &"default"
@export var persistent_id: StringName
@export var actor_definition_id: StringName
@export var portal_target_map_id: StringName
@export var portal_target_spawn_id: StringName
@export var completed_behavior: CompletedBehavior = CompletedBehavior.NONE
@export var event: StoryEvent

var binding := StoryBinding.new()


func _ready() -> void:
	add_to_group(&"story_interactables_3d")


func configure_story(default_event: StoryEvent) -> void:
	binding.event = event if event != null else default_event
	binding.trigger_id = trigger_id


func story_origin(map_id: StringName) -> StoryOrigin:
	return StoryOrigin.create(map_id, persistent_id, actor_definition_id)


func apply_completed() -> void:
	if completed_behavior == CompletedBehavior.HIDE_OWNER:
		var target := get_parent()
		target.visible = false
		target.process_mode = Node.PROCESS_MODE_DISABLED


func is_available() -> bool:
	return is_visible_in_tree() and process_mode != Node.PROCESS_MODE_DISABLED

