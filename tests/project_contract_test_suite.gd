class_name ProjectContractTestSuite
extends RefCounted

const TEST_REALM_MIGRATION := "res://tests/.tmp_realm_migration.tres"
const TEST_MIGRATION_DIR := "res://tests/.tmp_content_migrations"
const ORIGINAL_3D_ASSET_VALIDATOR := preload(
	"res://game/presentation/action_combat_3d/original_3d_asset_validator.gd"
)
const FRAMEWORK_FORBIDDEN_TOKENS: Array[String] = [
	"res://game/",
	"res://assets/original/",
	"map.roadside",
	"story.roadside",
	"item.roadside",
	"framework-lab",
]
const RUNTIME_FORBIDDEN_TOKENS: Array[String] = [
	"GameSession",
	"GameFlow",
	"EventSequence",
	"EventAction",
	"/root/",
]

var _failures: PackedStringArray = []


func run() -> PackedStringArray:
	_test_display_baseline()
	_test_framework_boundary()
	_test_runtime_architecture_terms()
	_test_content_database()
	_test_content_catalog_round_trip()
	_test_realm_content_migration()
	_test_original_assets()
	_test_original_3d_assets()
	return _failures


func _test_display_baseline() -> void:
	var viewport_width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var viewport_height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	var window_width := int(ProjectSettings.get_setting("display/window/size/window_width_override", 0))
	var window_height := int(ProjectSettings.get_setting("display/window/size/window_height_override", 0))
	_expect(
		viewport_width == 640 and viewport_height == 360,
		"formal slice should use a 640x360 internal viewport, got %dx%d"
		% [viewport_width, viewport_height]
	)
	_expect(
		window_width == 1280 and window_height == 720,
		"default window should be an exact 2x presentation, got %dx%d"
		% [window_width, window_height]
	)
	_expect(
		ProjectSettings.get_setting("display/window/stretch/aspect") == "keep",
		"viewport presentation should preserve the 16:9 aspect ratio"
	)
	_expect(
		ProjectSettings.get_setting("display/window/stretch/mode") == "viewport",
		"world and UI should share the root viewport stretch"
	)
	_expect(
		ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer",
		"pixel presentation should use integer viewport scaling"
	)
	_expect(
		bool(ProjectSettings.get_setting("display/window/size/resizable", false)),
		"players should be able to resize the presentation window"
	)


func _test_framework_boundary() -> void:
	var paths := PackedStringArray()
	_collect_source_files("res://framework", paths)
	_expect(not paths.is_empty(), "framework boundary check should find source files")
	for path: String in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		_expect(file != null, "framework boundary check should read %s" % path)
		if file == null:
			continue
		var source := file.get_as_text()
		file.close()
		for token: String in FRAMEWORK_FORBIDDEN_TOKENS:
			_expect(
				not source.contains(token),
				"framework file %s must not depend on game content token %s" % [path, token]
			)


func _test_runtime_architecture_terms() -> void:
	var paths := PackedStringArray()
	_collect_source_files("res://framework", paths)
	_collect_source_files("res://game", paths)
	var class_name_pattern := RegEx.new()
	class_name_pattern.compile("(?m)^class_name\\s+([A-Za-z0-9_]+)")
	var public_callable_pattern := RegEx.new()
	public_callable_pattern.compile(
		"(?m)^var\\s+[A-Za-z][A-Za-z0-9_]*\\s*:\\s*Callable\\b"
	)
	var forbidden_name_patterns: Array[RegEx] = []
	for token: String in RUNTIME_FORBIDDEN_TOKENS:
		if token == "/root/":
			continue
		var pattern := RegEx.new()
		pattern.compile("\\b%s\\b" % token)
		forbidden_name_patterns.append(pattern)
	for path: String in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		_expect(file != null, "runtime architecture check should read %s" % path)
		if file == null:
			continue
		var source := file.get_as_text()
		file.close()
		for index: int in range(forbidden_name_patterns.size()):
			_expect(
				forbidden_name_patterns[index].search(source) == null,
				"runtime file %s must not reintroduce architecture token %s"
				% [path, RUNTIME_FORBIDDEN_TOKENS[index]]
			)
		_expect(
			not source.contains("/root/"),
			"runtime file %s must not use absolute scene-tree paths" % path
		)
		_expect(
			public_callable_pattern.search(source) == null,
			"runtime file %s must expose typed methods instead of public Callable fields" % path
		)
		for match_result: RegExMatch in class_name_pattern.search_all(source):
			var class_name_value := match_result.get_string(1)
			_expect(
				not class_name_value.ends_with("Manager"),
				"runtime class %s must use an ownership-specific name instead of Manager"
				% class_name_value
			)
			_expect(
				not class_name_value.ends_with("Session")
				or class_name_value == "BattleSession",
				"runtime class %s must not introduce another Session abstraction"
				% class_name_value
			)


func _test_content_database() -> void:
	const database_path := "res://content/content_database.tres"
	var database := load(database_path) as ContentDatabase
	var errors := database.build_index()
	_expect(errors.is_empty(), "original content database should validate: %s" % [errors])
	var project_diagnostics := ContentProjectValidator.validate(database, database_path)
	_expect(
		project_diagnostics.is_empty(),
		"content project validator should accept the formal content: %s"
		% [project_diagnostics]
	)
	_expect(database.actors.size() == 1, "formal slice should register one original actor")
	_expect(database.realms.size() == 2, "formal slice should register two cultivation realms")
	_expect(database.foundations.size() == 2, "formal slice should register two dao foundations")
	_expect(database.npcs.size() == 2, "formal slice should register the shopkeeper and lantern keeper")
	_expect(database.maps.size() == 5, "formal slice should register gathering, combat, and lantern pass maps")
	_expect(database.items.size() == 6, "formal content should register gathering, medicine, catalyst, and build equipment")
	_expect(database.skills.size() == 3, "formal combat slice should register two base skills and one foundation ultimate")
	_expect(database.statuses.size() == 1, "formal combat slice should register one timed status")
	_expect(database.enemies.size() == 6, "formal combat content should register roadside and lantern-pass enemies")
	_expect(database.encounters.size() == 7, "formal combat content should register finite roadside and MVP encounters")
	_expect(database.shops.is_empty(), "formal slice should not keep obsolete lab shops")
	_expect(
		database.story_directories == PackedStringArray([
			"res://game/roadside/stories",
			"res://game/roadside/action_combat_3d/stories",
		]),
		"formal content should scan both roadside story directories"
	)
	var scanned := ContentSourceScanner.new().scan_story_resources(database.story_directories)
	_expect(scanned.get("diagnostics", []).is_empty(), "configured story directory should scan cleanly")
	_expect(scanned.get("stories", []).size() == 3, "formal story scan should include gathering, combat, and lantern modules")
	_expect(
		database.actor(&"actor.roadside.traveler") != null,
		"database should expose the original traveler ID"
	)
	_expect(
		database.actor(&"actor.roadside.traveler").field_model_3d != null,
		"the formal traveler definition should own its reusable 3D field model"
	)
	_expect(
		database.npc(&"npc.roadside.shopkeeper") != null
		and database.npc(&"npc.roadside.shopkeeper").field_model_3d != null,
		"database should expose the shopkeeper NPC and its reusable 3D field model"
	)
	_expect(
		database.map(&"map.roadside.shop") != null,
		"database should expose the roadside shop ID"
	)
	_expect(
		database.map(&"map.roadside.herb_slope") != null,
		"database should expose the herb slope ID"
	)
	_expect(
		database.map(&"map.roadside.north_slope_wilds") != null,
		"database should expose the large generated exploration map ID"
	)
	_expect(
		database.item(&"item.roadside.fanqing_grass") != null,
		"database should expose the gathering material ID"
	)
	_expect(
		database.map(&"map.roadside.north_slope_pack") != null
		and database.encounter(&"encounter.roadside.north_slope_pack") != null,
		"database should expose the formal 3D combat slice"
	)
	_expect(
		database.map(&"map.roadside.shop").story_module is RoadsideGatheringStory
		and database.map(&"map.roadside.herb_slope").story_module is RoadsideGatheringStory
		and database.map(&"map.roadside.north_slope_wilds").story_module is RoadsideGatheringStory
		and database.map(&"map.roadside.lantern_pass").story_module is LanternPassStory
		and database.map(&"map.roadside.north_slope_pack").story_module is NorthSlopePackStory,
		"every map should declare its objective StoryModule without a GameRoot fallback"
	)


func _test_content_catalog_round_trip() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	var catalog := ContentCatalog.new()
	catalog.build(database)
	var enemy_schema := ContentSchemaCatalog.schema_for("enemy")
	var enemy_field_names: Array[String] = []
	for field: Dictionary in enemy_schema.get("fields", []):
		enemy_field_names.append(String(field.get("name", "")))
	var equipment_schema := ContentSchemaCatalog.schema_for("equipment")
	_expect(
		enemy_schema.get("resource_class") == "EnemyDefinition"
		and enemy_field_names.has("is_boss")
		and enemy_field_names.has("charge_staggers_on_pillar")
		and enemy_schema.get("create_required_options") == ["path", "scene"]
		and equipment_schema.get("id_prefix") == "item.",
		"content schema catalog should preserve CLI type fields, creation options, and ID prefixes"
	)
	_expect(
		ContentOptionParser.target_rule("single-enemy")
		== SkillDefinition.TargetRule.SINGLE_ENEMY
		and ContentOptionParser.item_category("key-item")
		== ItemDefinition.Category.KEY_ITEM
		and ContentOptionParser.combat_style("charger")
		== EnemyDefinition.CombatStyle.CHARGER
		and ContentOptionParser.reward_policy("allow-partial")
		== RewardPolicy.Value.ALLOW_PARTIAL
		and ContentOptionParser.boolean(" TRUE ") == true
		and ContentOptionParser.boolean("yes") == null,
		"content option parser should normalize supported CLI values and reject unknown booleans"
	)
	var document := catalog.export_document()
	var qi_record := catalog.find("realm", &"realm.qi_refining")
	var sharp_record := catalog.find("foundation", &"foundation.sharp_metal")
	var medicine_record := catalog.find("item", &"item.roadside.wound_powder")
	var skill_record := catalog.find("skill", &"skill.roadside.wind_edge")
	_expect(
		qi_record.get("properties", {}).get("layer_cultivation_costs", [])
		== [20, 25, 30, 35, 40, 50, 60, 70],
		"catalog export should preserve PackedInt32Array cultivation costs"
	)
	_expect(
		String(sharp_record.get("properties", {}).get("aura_color", "")).length() == 8,
		"catalog export should encode foundation aura colors as editable RGBA"
	)
	_expect(
		medicine_record.get("properties", {}).get("icon")
		== "res://assets/original/ui/actions/potion.svg"
		and medicine_record.get("properties", {}).get("can_discard") == true
		and skill_record.get("properties", {}).get("icon")
		== "res://assets/original/ui/actions/flying_sword.svg",
		"catalog export should expose item permissions and data-driven icon paths"
	)
	var reapplied := ContentDocumentApplier.new().apply(document, catalog)
	_expect(
		reapplied.get("ok", false) and int(reapplied.get("change_count", -1)) == 0,
		"exported cultivation content should apply back without drift: %s" % [reapplied]
	)




func _test_realm_content_migration() -> void:
	_remove_if_exists(TEST_REALM_MIGRATION)
	var migration_file := TEST_MIGRATION_DIR.path_join(
		"realm_test_before_to_realm_test_after.json"
	)
	_remove_if_exists(migration_file)
	var realm := CultivationRealmDefinition.new()
	realm.id = &"realm.test_before"
	realm.display_name = "迁移测试境界"
	realm.max_layer = 1
	_expect(
		ResourceSaver.save(realm, TEST_REALM_MIGRATION) == OK,
		"realm migration fixture should save"
	)
	realm = load(TEST_REALM_MIGRATION) as CultivationRealmDefinition
	var database := ContentDatabase.new()
	database.realms.assign([realm])
	var result := ContentMigration.new().rename_id(
		"realm",
		&"realm.test_before",
		&"realm.test_after",
		database,
		TEST_MIGRATION_DIR
	)
	var migrated_text := FileAccess.get_file_as_string(TEST_REALM_MIGRATION)
	_expect(
		result.get("ok", false)
		and migrated_text.contains("realm.test_after")
		and not migrated_text.contains("realm.test_before")
		and FileAccess.file_exists(migration_file),
		"rename-id should migrate realm IDs and write an audit record: %s" % [result]
	)
	_remove_if_exists(TEST_REALM_MIGRATION)
	_remove_if_exists(migration_file)
	_remove_directory_if_empty(TEST_MIGRATION_DIR)


func _test_original_assets() -> void:
	var diagnostics := AssetLibrary.validate_assets()
	_expect(diagnostics.is_empty(), "required original assets should exist: %s" % [diagnostics])
	for path: String in AssetLibrary.REQUIRED_ASSETS:
		_expect(not path.begins_with("res://generated/"), "runtime assets must not use generated/")


func _test_original_3d_assets() -> void:
	for failure: String in ORIGINAL_3D_ASSET_VALIDATOR.validate_assets():
		_expect(false, failure)




func _collect_source_files(directory_path: String, result: PackedStringArray) -> void:
	var directory := DirAccess.open(directory_path)
	_expect(directory != null, "source boundary check should open %s" % directory_path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		if file_name.get_extension().to_lower() in ["gd", "tscn", "tres"]:
			result.append(directory_path.path_join(file_name))
	for child_name: String in directory.get_directories():
		if not child_name.begins_with("."):
			_collect_source_files(directory_path.path_join(child_name), result)


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_directory_if_empty(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
