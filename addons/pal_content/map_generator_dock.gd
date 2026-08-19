@tool
class_name MapGeneratorDock
extends VBoxContainer

var _editor_interface: EditorInterface
var _profile_picker: EditorResourcePicker
var _seed_input: SpinBox
var _preview_button: Button
var _undo_button: Button
var _validate_button: Button
var _bake_button: Button
var _summary: RichTextLabel
var _status: Label
var _preview_active: bool = false


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface


func _ready() -> void:
	name = "Map Generator"
	custom_minimum_size = Vector2(330.0, 420.0)
	_build_ui()


func _build_ui() -> void:
	var heading := Label.new()
	heading.text = "Ecological Map Generator"
	heading.add_theme_font_size_override("font_size", 16)
	add_child(heading)
	var profile_label := Label.new()
	profile_label.text = "Generation Profile"
	add_child(profile_label)
	_profile_picker = EditorResourcePicker.new()
	_profile_picker.base_type = "MapGenerationProfile"
	_profile_picker.resource_changed.connect(_on_profile_changed)
	add_child(_profile_picker)
	var seed_row := HBoxContainer.new()
	add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_row.add_child(seed_label)
	_seed_input = SpinBox.new()
	_seed_input.min_value = 1.0
	_seed_input.max_value = 2_147_483_646.0
	_seed_input.step = 1.0
	_seed_input.allow_greater = false
	_seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_input)
	var new_seed_button := Button.new()
	new_seed_button.text = "New"
	new_seed_button.pressed.connect(_new_seed)
	seed_row.add_child(new_seed_button)
	var action_row := HBoxContainer.new()
	add_child(action_row)
	_preview_button = Button.new()
	_preview_button.text = "Preview"
	_preview_button.pressed.connect(_preview)
	action_row.add_child(_preview_button)
	_undo_button = Button.new()
	_undo_button.text = "Undo Preview"
	_undo_button.disabled = true
	_undo_button.pressed.connect(_undo_preview)
	action_row.add_child(_undo_button)
	var validation_row := HBoxContainer.new()
	add_child(validation_row)
	_validate_button = Button.new()
	_validate_button.text = "Validate"
	_validate_button.pressed.connect(_validate)
	validation_row.add_child(_validate_button)
	_bake_button = Button.new()
	_bake_button.text = "Bake"
	_bake_button.pressed.connect(_bake)
	validation_row.add_child(_bake_button)
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.custom_minimum_size.y = 150.0
	add_child(_summary)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Select a profile and open its target MapGameScene3D."
	add_child(_status)


func _on_profile_changed(resource_value: Resource) -> void:
	if _preview_active:
		_undo_preview()
	var profile := resource_value as MapGenerationProfile
	if profile != null:
		_seed_input.value = profile.seed
	_status.text = "Profile ready." if profile != null else "Select a MapGenerationProfile."


func _new_seed() -> void:
	_seed_input.value = int(Time.get_unix_time_from_system()) % 2_147_483_646 + 1


func _preview() -> void:
	if _preview_active:
		_undo_preview()
	var context := _generation_context()
	if not bool(context.get("ok", false)):
		return
	var profile := context.get("profile") as MapGenerationProfile
	var map_scene := context.get("scene") as MapGameScene3D
	var plan := context.get("plan") as MapGenerationPlan
	var snapshot := MapGenerationSceneSnapshot.capture(map_scene)
	var undo_redo := _editor_interface.get_editor_undo_redo()
	undo_redo.create_action("Preview ecological map generation")
	undo_redo.add_do_method(self, "_apply_preview", profile, plan)
	undo_redo.add_undo_method(self, "_restore_preview", snapshot)
	undo_redo.commit_action()
	_preview_active = true
	_undo_button.disabled = false
	_status.text = "Preview applied without saving. Use Undo Preview or Bake."


func _undo_preview() -> void:
	if not _preview_active or _editor_interface == null:
		return
	_editor_interface.get_editor_undo_redo().undo()
	_preview_active = false
	_undo_button.disabled = true
	_status.text = "Preview reverted."


func _validate() -> void:
	var context := _generation_context()
	if bool(context.get("ok", false)):
		_status.text = "Generation plan is valid."


func _bake() -> void:
	if _preview_active:
		_undo_preview()
	var context := _generation_context()
	if not bool(context.get("ok", false)):
		return
	var profile := context.get("profile") as MapGenerationProfile
	var plan := context.get("plan") as MapGenerationPlan
	var save_error := _editor_interface.save_scene()
	if save_error != OK:
		_status.text = "Could not save the manual scene before baking: %s" % error_string(save_error)
		return
	var result := MapGenerationBaker.new().bake_atomic(profile, plan)
	if not bool(result.get("ok", false)):
		_show_diagnostics(result.get("diagnostics", []))
		_status.text = "Bake failed; the target scene was left unchanged."
		return
	_preview_active = false
	_undo_button.disabled = true
	_editor_interface.reload_scene_from_path(profile.target_scene_path)
	_status.text = "Baked and reloaded %s." % profile.target_scene_path


func _generation_context() -> Dictionary:
	var source_profile := _profile_picker.edited_resource as MapGenerationProfile
	if source_profile == null:
		_status.text = "Select a MapGenerationProfile first."
		return {"ok": false}
	if _editor_interface == null:
		_status.text = "Editor interface is unavailable."
		return {"ok": false}
	var map_scene := _editor_interface.get_edited_scene_root() as MapGameScene3D
	if map_scene == null:
		_status.text = "Open the profile target MapGameScene3D first."
		return {"ok": false}
	if map_scene.scene_file_path != source_profile.target_scene_path:
		_status.text = "Open target scene: %s" % source_profile.target_scene_path
		return {"ok": false}
	var profile := source_profile.duplicate(true) as MapGenerationProfile
	profile.seed = int(_seed_input.value)
	profile.set_authoring_source_path(source_profile.resource_path)
	var plan := MapGenerator.new().generate(profile, map_scene)
	_show_plan(plan)
	if not plan.is_valid():
		_status.text = "Generation plan has %d error(s)." % plan.diagnostics.size()
		return {"ok": false, "profile": profile, "scene": map_scene, "plan": plan}
	return {"ok": true, "profile": profile, "scene": map_scene, "plan": plan}


func _apply_preview(profile: MapGenerationProfile, plan: MapGenerationPlan) -> void:
	var map_scene := _editor_interface.get_edited_scene_root() as MapGameScene3D
	if map_scene == null:
		return
	var diagnostics := MapGenerationBaker.new().apply_plan(profile, plan, map_scene)
	if not diagnostics.is_empty():
		_show_diagnostics(diagnostics)


func _restore_preview(snapshot: MapGenerationSceneSnapshot) -> void:
	var map_scene := _editor_interface.get_edited_scene_root() as MapGameScene3D
	if map_scene != null:
		snapshot.restore(map_scene)


func _show_plan(plan: MapGenerationPlan) -> void:
	if plan == null:
		_summary.text = ""
		return
	var metrics := plan.metrics
	var lines := PackedStringArray([
		"[b]Plan[/b]  %s" % plan.plan_hash.left(12),
		"Cells: %s  Roads: %s  Props: %s"
		% [metrics.get("cell_count", 0), metrics.get("road_cell_count", 0), metrics.get("prop_count", 0)],
		"Habitats:",
	])
	var habitat_counts: Dictionary = metrics.get("habitat_counts", {})
	var tags := PackedStringArray(habitat_counts.keys())
	tags.sort()
	for tag: String in tags:
		lines.append("  %s: %s" % [tag, habitat_counts[tag]])
	_summary.text = "\n".join(lines)
	if not plan.diagnostics.is_empty():
		_show_diagnostics(plan.diagnostics)


func _show_diagnostics(diagnostics_value: Variant) -> void:
	var lines := PackedStringArray(["[b]Diagnostics[/b]"])
	if diagnostics_value is Array:
		for diagnostic: Dictionary in diagnostics_value:
			lines.append("%s: %s" % [diagnostic.get("code", "error"), diagnostic.get("message", "")])
	_summary.text = "\n".join(lines)
