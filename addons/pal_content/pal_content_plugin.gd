@tool
extends EditorPlugin

var _dock: ContentDatabaseDock


func _enter_tree() -> void:
	_dock = ContentDatabaseDock.new()
	_dock.resource_open_requested.connect(_open_resource)
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _open_resource(resource_value: Resource) -> void:
	if resource_value != null:
		get_editor_interface().edit_resource(resource_value)
