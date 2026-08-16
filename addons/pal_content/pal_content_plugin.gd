@tool
extends EditorPlugin

var _dock: ContentDatabaseDock
var _map_generator_dock: MapGeneratorDock


func _enter_tree() -> void:
	_dock = ContentDatabaseDock.new()
	_dock.resource_open_requested.connect(_open_resource)
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _dock)
	_map_generator_dock = MapGeneratorDock.new()
	_map_generator_dock.setup(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _map_generator_dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _map_generator_dock != null:
		remove_control_from_docks(_map_generator_dock)
		_map_generator_dock.queue_free()
		_map_generator_dock = null


func _open_resource(resource_value: Resource) -> void:
	if resource_value != null:
		get_editor_interface().edit_resource(resource_value)
