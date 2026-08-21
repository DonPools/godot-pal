class_name StoryInteractable3D
extends PointerTarget3D

enum CompletedBehavior {
	NONE,
	HIDE_OWNER,
}

@export var binding: StoryBinding
@export var persistent_id: StringName
@export var actor_definition_id: StringName
@export var interaction_label: String
@export var portal_target_map_id: StringName
@export var portal_target_spawn_id: StringName
@export var completed_behavior: CompletedBehavior = CompletedBehavior.NONE


func _ready() -> void:
	super._ready()
	add_to_group(&"story_interactables_3d")


func configure_portal(destination: MapDestination) -> void:
	var event := ScenePortalEvent.new()
	event.destination = destination
	binding = StoryBinding.new()
	binding.event = event
	binding.trigger_id = &"default"


func story_origin(map_id: StringName) -> StoryOrigin:
	return StoryOrigin.create(map_id, persistent_id, actor_definition_id)


func apply_completed() -> void:
	set_pointer_enabled(false)
	if completed_behavior == CompletedBehavior.HIDE_OWNER:
		var target := get_parent()
		target.visible = false
		target.process_mode = Node.PROCESS_MODE_DISABLED


func is_available() -> bool:
	return (
		pointer_enabled
		and is_visible_in_tree()
		and process_mode != Node.PROCESS_MODE_DISABLED
	)
