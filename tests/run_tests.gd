extends SceneTree

const MAP_GENERATION_TEST_SUITE := preload(
	"res://tests/map_generation/map_generation_test_suite.gd"
)
const BATTLE_SESSION_TEST_SUITE := preload(
	"res://tests/battle/battle_session_test_suite.gd"
)
const R9_FIELD_TEST_TEST_SUITE := preload(
	"res://tests/r9_field_test_test_suite.gd"
)
const SETTINGS_TEST_SUITE := preload(
	"res://tests/settings/settings_test_suite.gd"
)
const CONTENT_FACTORY_TEST_SUITE := preload(
	"res://tests/tooling/content_factory_test_suite.gd"
)
const GAME_STATE_TEST_SUITE := preload(
	"res://tests/state/game_state_test_suite.gd"
)
const PROJECT_CONTRACT_TEST_SUITE := preload(
	"res://tests/project_contract_test_suite.gd"
)
const STORY_CONTENT_TEST_SUITE := preload(
	"res://tests/story/story_content_test_suite.gd"
)
const FORMAL_MAP_TEST_SUITE := preload(
	"res://tests/maps/formal_map_test_suite.gd"
)
const RUNTIME_INTEGRATION_TEST_SUITE := preload(
	"res://tests/runtime/runtime_integration_test_suite.gd"
)

var _failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_ensure_input_actions()
	_test_project_contracts()
	_test_content_factories()
	_test_map_generation()
	await _test_story_content()
	await _test_formal_maps()
	_test_game_state()
	_test_battle_session()
	_test_settings()
	_test_r9_field_tests()
	await _test_runtime_integration()
	if _failures.is_empty():
		print("roadside gathering slice tests passed")
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)


func _test_project_contracts() -> void:
	_failures.append_array(PROJECT_CONTRACT_TEST_SUITE.new().run())


func _test_content_factories() -> void:
	_failures.append_array(CONTENT_FACTORY_TEST_SUITE.new().run())


func _test_map_generation() -> void:
	for failure: String in MAP_GENERATION_TEST_SUITE.new().run():
		_expect(false, failure)


func _test_battle_session() -> void:
	for failure: String in BATTLE_SESSION_TEST_SUITE.new().run():
		_expect(false, failure)


func _test_story_content() -> void:
	_failures.append_array(await STORY_CONTENT_TEST_SUITE.new().run(self))


func _test_formal_maps() -> void:
	_failures.append_array(await FORMAL_MAP_TEST_SUITE.new().run(self))


func _test_game_state() -> void:
	_failures.append_array(GAME_STATE_TEST_SUITE.new().run())


func _test_settings() -> void:
	_failures.append_array(SETTINGS_TEST_SUITE.new().run(self))


func _test_r9_field_tests() -> void:
	_failures.append_array(R9_FIELD_TEST_TEST_SUITE.new().run(self))


func _test_runtime_integration() -> void:
	_failures.append_array(await RUNTIME_INTEGRATION_TEST_SUITE.new().run(self))


func _ensure_input_actions() -> void:
	for action: StringName in [
		&"move_north", &"move_south", &"move_west", &"move_east",
		&"aim_north", &"aim_south", &"aim_west", &"aim_east",
		&"interact", &"menu", &"combat_attack", &"combat_skill_one",
		&"combat_skill_two", &"combat_skill_three", &"combat_dodge", &"combat_item",
		&"combat_stand_ground", &"combat_force_move", &"combat_target_next",
	]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
