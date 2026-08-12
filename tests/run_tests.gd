extends SceneTree

const TEST_SAVE := "user://framework_lab_test.json"
const TEST_SAVE_BOUNDARY := "user://framework_lab_boundary_test.json"
const CLI_TEMP_DIRECTORY := "res://tests/.tmp_content_cli"
const FakeStoryContextClass := preload("res://tests/fake_story_context.gd")

var _failures: PackedStringArray = []
var _scene_stack_result: Variant
var _scene_stack_result_received: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_story_trace()
	_test_game_run_round_trip()
	_test_rpg_domain_rules()
	await _test_bridge_story_outcomes()
	_test_battle_rules()
	_test_save_service_boundaries()
	_test_asset_manifest_validation()
	_test_content_cli_commands()
	_test_animated_sprite_scene_defaults()
	_test_map_scene_content()
	await _test_scene_stack()
	await _test_scene_smoke()
	if _failures.is_empty():
		print("framework-lab tests passed")
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)


func _test_story_trace() -> void:
	var story := load("res://stories/lab/borrowed_umbrella.tres") as BorrowedUmbrellaStory
	var fake := FakeStoryContextClass.new()
	await story.run(&"enter_hall", fake)
	_expect(fake.stage == &"met_innkeeper", "entry should introduce the innkeeper")
	await story.run(&"talk_innkeeper", fake)
	_expect(fake.stage == &"looking_for_owner", "innkeeper should start the search")
	await story.run(&"enter_courtyard", fake)
	_expect(
		fake.flags.has(&"flag.story.lab.borrowed_umbrella.courtyard_seen"),
		"courtyard entry flag should be set"
	)
	await story.run(&"talk_traveler", fake)
	_expect(fake.stage == &"owner_found", "traveler should identify the umbrella")
	await story.run(&"take_umbrella", fake)
	_expect(fake.source_completed, "umbrella source should complete exactly once")
	_expect(fake.stage == &"umbrella_found", "umbrella interaction should advance the story")
	await story.run(&"talk_innkeeper", fake)
	_expect(fake.stage == &"completed", "returning the umbrella should finish the story")
	_expect(
		fake.shown_blocks == [
			&"opening",
			&"innkeeper_request",
			&"courtyard_first",
			&"traveler_reveal",
			&"umbrella_take",
			&"innkeeper_finish",
		],
		"story dialogue trace should remain deterministic"
	)


func _test_game_run_round_trip() -> void:
	var run := _new_test_run()
	run.story.set_stage(&"story.lab.borrowed_umbrella", &"owner_found")
	run.flags.set_value(&"flag.test")
	run.world.complete(&"map.lab.rain_courtyard", &"old_umbrella")
	run.location.map_id = &"map.lab.rain_courtyard"
	run.location.position = Vector2(12.0, 34.0)
	run.location.has_exact_position = true
	var restored := GameRun.from_dictionary(run.to_dictionary())
	_expect(restored != null, "GameRun should decode its own save payload")
	if restored == null:
		return
	_expect(
		restored.story.get_stage(&"story.lab.borrowed_umbrella", &"") == &"owner_found",
		"StoryState should round-trip"
	)
	_expect(restored.flags.is_set(&"flag.test"), "GameFlags should round-trip")
	_expect(
		restored.world.is_completed(&"map.lab.rain_courtyard", &"old_umbrella"),
		"WorldState should round-trip"
	)
	_expect(restored.location.position == Vector2(12.0, 34.0), "LocationState should round-trip")
	_expect(restored.party.leader() != null, "PartyState should round-trip")
	_expect(restored.economy.money == 40, "EconomyState should round-trip")


func _test_rpg_domain_rules() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	var database_errors := database.build_index()
	_expect(database_errors.is_empty(), "RPG content should index: %s" % [database_errors])
	var run := GameRun.new_game(database)
	var leader := run.party.leader()
	var actor_definition := database.actor(&"actor.li_xiaoyao")
	_expect(leader != null, "new game should create the configured party leader")
	_expect(
		leader.equipment.get(&"weapon") == &"item.lab.wooden_sword",
		"ActorState should store initial equipment by semantic ID"
	)
	_expect(&"skill.lab.quiet_breath" in leader.skill_ids, "ActorState should store initial skills")

	var herb := database.item(&"item.lab.healing_herb")
	var herb_reward := run.inventory.add_item(herb, 2)
	_expect(herb_reward.succeeded(), "InventoryState should atomically add an item reward")
	leader.hp = 50
	var heal_result := herb.effects[0].apply(EffectContext.create(herb.id, leader, actor_definition))
	_expect(heal_result.changed_amount == 35 and leader.hp == 85, "HealEffect should clamp against max HP")
	var removed := run.inventory.remove_item(herb, 1)
	_expect(removed.succeeded() and run.inventory.quantity(herb.id) == 1, "item use should consume one item")

	var full_inventory := InventoryState.new()
	_expect(full_inventory.add_item(herb, herb.max_stack).succeeded(), "fixture should fill one stack")
	var rejected := full_inventory.add_item(herb, 1, RewardPolicy.Value.ALL_OR_NOTHING)
	_expect(not rejected.changed(), "ALL_OR_NOTHING should not partially mutate a full stack")
	_expect(full_inventory.quantity(herb.id) == herb.max_stack, "rejected rewards should preserve quantity")

	var draught := database.item(&"item.lab.spirit_draught")
	var partial_inventory := InventoryState.new()
	partial_inventory.add_item(draught, draught.max_stack - 1)
	var partial := partial_inventory.add_item(draught, 3, RewardPolicy.Value.ALLOW_PARTIAL)
	_expect(
		partial.changed_quantity == 1 and partial.rejected_quantity == 2,
		"ALLOW_PARTIAL should report exact accepted and rejected quantities"
	)
	leader.mp = 2
	var restore_result := draught.effects[0].apply(
		EffectContext.create(draught.id, leader, actor_definition)
	)
	_expect(restore_result.changed_amount == 8 and leader.mp == 10, "RestoreMpEffect should update ActorState")
	_expect(run.economy.try_spend(12) and run.economy.money == 28, "EconomyState should spend atomically")
	_expect(not run.economy.try_spend(99) and run.economy.money == 28, "failed spending should preserve money")

	var shop := database.shop(&"shop.lab.herbal_room")
	var purchase_run := GameRun.new_game(database)
	var purchase := ShopTransaction.buy(purchase_run, shop.entries[0])
	_expect(purchase.purchased(), "ShopTransaction should purchase a configured item")
	_expect(
		purchase_run.economy.money == 28
		and purchase_run.inventory.quantity(herb.id) == 1,
		"shop purchase should commit money and inventory together"
	)
	purchase_run.economy.money = 0
	var rejected_purchase := ShopTransaction.buy(purchase_run, shop.entries[1])
	_expect(
		rejected_purchase.outcome == ShopResult.Outcome.INSUFFICIENT_FUNDS,
		"ShopTransaction should report insufficient funds"
	)
	_expect(
		purchase_run.inventory.quantity(draught.id) == 0,
		"failed purchase should not mutate inventory"
	)
	var use_run := GameRun.new_game(database)
	use_run.inventory.add_item(herb)
	var use_leader := use_run.party.leader()
	use_leader.hp = 65
	var use_result := ItemUseTransaction.use_on_actor(use_run, herb, use_leader, actor_definition)
	_expect(use_result.used() and use_leader.hp == 100, "ItemUseTransaction should apply item effects")
	_expect(use_run.inventory.quantity(herb.id) == 0, "successful item use should consume exactly one")
	use_run.inventory.add_item(herb)
	var no_effect := ItemUseTransaction.use_on_actor(use_run, herb, use_leader, actor_definition)
	_expect(no_effect.outcome == ItemUseResult.Outcome.NO_EFFECT, "full HP should reject a healing item")
	_expect(use_run.inventory.quantity(herb.id) == 1, "no-effect item use should preserve inventory")


func _test_bridge_story_outcomes() -> void:
	var story := load("res://stories/lab/bridge_ambush.tres") as BridgeAmbushStory
	for outcome: BattleResult.Outcome in [
		BattleResult.Outcome.VICTORY,
		BattleResult.Outcome.ESCAPED,
		BattleResult.Outcome.DEFEAT,
	]:
		var fake := FakeStoryContextClass.new()
		fake.next_battle_result.outcome = outcome
		await story.run(&"confront_bandit", fake)
		match outcome:
			BattleResult.Outcome.VICTORY:
				_expect(fake.source_completed and fake.stage == &"completed", "Victory should complete the battle source")
			BattleResult.Outcome.ESCAPED:
				_expect(not fake.source_completed and fake.stage == &"escaped", "Escaped should preserve the battle source")
			BattleResult.Outcome.DEFEAT:
				_expect(fake.party_restored, "Defeat should restore the party before travel")
				_expect(fake.recorded_pending_map == story.safe_map, "Defeat should register terminal safe travel")


func _test_battle_rules() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	var errors := database.build_index()
	_expect(errors.is_empty(), "battle content should index: %s" % [errors])
	var encounter := database.encounter(&"encounter.lab.bridge_ambush")

	var escape_run := GameRun.new_game(database)
	var escape_session := BattleSession.create(encounter, escape_run, database)
	var escape_hp := escape_session.player.hp
	escape_session.execute(BattleSession.Command.DEFEND)
	_expect(escape_session.player.hp > escape_hp - encounter.enemies[0].enemy.attack, "defend should reduce incoming damage")
	escape_session.execute(BattleSession.Command.ESCAPE)
	var escaped := escape_session.commit_result()
	_expect(escaped.outcome == BattleResult.Outcome.ESCAPED, "escape command should return Escaped")
	_expect(escape_run.economy.money == 40, "Escaped should not grant victory money")

	var victory_run := GameRun.new_game(database)
	victory_run.inventory.add_item(database.item(&"item.lab.healing_herb"))
	var victory_session := BattleSession.create(encounter, victory_run, database)
	victory_session.player.hp = 50
	victory_session.execute(BattleSession.Command.ITEM)
	_expect(victory_session.player.hp == 76, "battle item should heal before the enemy counterattack")
	_expect(victory_run.inventory.quantity(&"item.lab.healing_herb") == 1, "battle item use should commit only at outcome")
	victory_session.execute(BattleSession.Command.SKILL)
	while not victory_session.finished:
		victory_session.execute(BattleSession.Command.ATTACK)
	var victory := victory_session.commit_result()
	_expect(victory.is_victory(), "attack and skill commands should reach Victory")
	_expect(victory_run.economy.money == 56, "Victory should commit encounter money")
	_expect(victory_run.inventory.quantity(&"item.lab.healing_herb") == 1, "Victory should commit item use and one dropped herb")

	var defeat_run := GameRun.new_game(database)
	var defeat_session := BattleSession.create(encounter, defeat_run, database)
	defeat_session.player.hp = 1
	defeat_session.execute(BattleSession.Command.ATTACK)
	var defeat := defeat_session.commit_result()
	_expect(defeat.outcome == BattleResult.Outcome.DEFEAT, "zero HP should return Defeat")
	_expect(defeat_run.party.leader().hp == 0, "Defeat should commit HP loss")
	_expect(defeat_run.economy.money == 40, "Defeat should not grant victory money")


func _test_save_service_boundaries() -> void:
	_cleanup_save_test_files(TEST_SAVE_BOUNDARY)
	var database := load("res://content/content_database.tres") as ContentDatabase
	database.build_index()
	var service := SaveService.new()
	service.configure(database)

	_write_save_fixture(TEST_SAVE_BOUNDARY, "{not valid json")
	_expect(service.load_run(TEST_SAVE_BOUNDARY) == null, "SaveService should reject damaged JSON")
	_expect(service.last_diagnostic.get("code") == "save_json_invalid", "damaged JSON should have a stable diagnostic")

	var unsupported := _new_test_run().to_dictionary()
	unsupported["save_version"] = 999
	_write_save_fixture(TEST_SAVE_BOUNDARY, JSON.stringify(unsupported))
	_expect(service.load_run(TEST_SAVE_BOUNDARY) == null, "SaveService should reject unknown save schemas")
	_expect(
		service.last_diagnostic.get("code") == "save_schema_unsupported",
		"unknown save schemas should have a stable diagnostic"
	)

	var unknown_map := _new_test_run().to_dictionary()
	unknown_map["location"]["map_id"] = "map.test.missing"
	_write_save_fixture(TEST_SAVE_BOUNDARY, JSON.stringify(unknown_map))
	_expect(service.load_run(TEST_SAVE_BOUNDARY) == null, "SaveService should reject unknown map IDs")
	_expect(service.last_diagnostic.get("code") == "save_content_invalid", "unknown maps should be diagnosed")

	var original := _new_test_run()
	original.story.set_stage(&"story.lab.borrowed_umbrella", &"owner_found")
	_expect(service.save_run(original, TEST_SAVE_BOUNDARY) == OK, "boundary fixture should save")
	var failing_service := FailingSaveService.new()
	failing_service.configure(database)
	failing_service.fail_next_temporary_install = true
	var replacement := _new_test_run()
	replacement.story.set_stage(&"story.lab.borrowed_umbrella", &"completed")
	_expect(
		failing_service.save_run(replacement, TEST_SAVE_BOUNDARY) == ERR_CANT_CREATE,
		"SaveService should report a failed atomic replacement"
	)
	_expect(
		failing_service.last_diagnostic.get("code") == "save_atomic_replace_failed",
		"atomic replacement failures should have a stable diagnostic"
	)
	var preserved := service.load_run(TEST_SAVE_BOUNDARY)
	_expect(preserved != null, "failed replacement should preserve the previous save")
	if preserved != null:
		_expect(
			preserved.story.get_stage(&"story.lab.borrowed_umbrella", &"") == &"owner_found",
			"failed replacement must roll back the previous save contents"
		)
	_expect(not FileAccess.file_exists(TEST_SAVE_BOUNDARY + ".tmp"), "failed save should remove its temporary file")
	_expect(not FileAccess.file_exists(TEST_SAVE_BOUNDARY + ".bak"), "successful rollback should consume its backup")

	var interrupted_backup := TEST_SAVE_BOUNDARY + ".bak"
	_expect(
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(TEST_SAVE_BOUNDARY),
			ProjectSettings.globalize_path(interrupted_backup)
		) == OK,
		"interrupted replacement fixture should move the previous save to backup"
	)
	_write_save_fixture(TEST_SAVE_BOUNDARY + ".tmp", "incomplete")
	var recovered := service.load_run(TEST_SAVE_BOUNDARY)
	_expect(recovered != null, "load should recover an interrupted replacement backup")
	_expect(FileAccess.file_exists(TEST_SAVE_BOUNDARY), "load recovery should restore the target save")
	_expect(not FileAccess.file_exists(interrupted_backup), "load recovery should consume the backup")
	_expect(not FileAccess.file_exists(TEST_SAVE_BOUNDARY + ".tmp"), "load recovery should discard stale temporary data")
	_cleanup_save_test_files(TEST_SAVE_BOUNDARY)
	failing_service.free()
	service.free()


func _write_save_fixture(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()


func _cleanup_save_test_files(path: String) -> void:
	for candidate: String in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _new_test_run() -> GameRun:
	var database := load("res://content/content_database.tres") as ContentDatabase
	database.build_index()
	return GameRun.new_game(database)


func _test_asset_manifest_validation() -> void:
	const MANIFEST_PATH := "res://generated/manifest.json"
	const GENERATED_ROOT := "res://generated/"
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var validator := AssetManifestValidator.new()
	var errors := validator.validate_data(manifest, GENERATED_ROOT, MANIFEST_PATH)
	_expect(errors.is_empty(), "generated asset manifest should validate: %s" % [errors])

	var missing_file_manifest := manifest.duplicate(true)
	missing_file_manifest["assets"][0]["path"] = "audio/music/missing.wav"
	errors = validator.validate_data(missing_file_manifest, GENERATED_ROOT, MANIFEST_PATH)
	_expect(
		_has_diagnostic(errors, "manifest_asset_file_missing"),
		"asset validator should reject missing output files"
	)

	var wrong_type_manifest := manifest.duplicate(true)
	wrong_type_manifest["assets"][0]["kind"] = "portrait"
	errors = validator.validate_data(wrong_type_manifest, GENERATED_ROOT, MANIFEST_PATH)
	_expect(
		_has_diagnostic(errors, "manifest_asset_extension_invalid"),
		"asset validator should reject kind/extension mismatches"
	)

	var wrong_hash_manifest := manifest.duplicate(true)
	wrong_hash_manifest["assets"][0]["sha256"] = "0".repeat(64)
	errors = validator.validate_data(wrong_hash_manifest, GENERATED_ROOT, MANIFEST_PATH)
	_expect(
		_has_diagnostic(errors, "manifest_asset_hash_mismatch"),
		"asset validator should reject hash mismatches"
	)

	var duplicate_manifest := manifest.duplicate(true)
	duplicate_manifest["assets"].append(duplicate_manifest["assets"][0].duplicate(true))
	errors = validator.validate_data(duplicate_manifest, GENERATED_ROOT, MANIFEST_PATH)
	_expect(
		_has_diagnostic(errors, "manifest_asset_source_duplicate"),
		"asset validator should reject repeated source keys"
	)


func _has_diagnostic(diagnostics: Array[Dictionary], code: String) -> bool:
	for diagnostic: Dictionary in diagnostics:
		if diagnostic.get("code") == code:
			return true
	return false


func _test_content_cli_commands() -> void:
	var list_result := _run_content_cli(["list", "--json"])
	_expect(list_result.exit_code == 0, "content list command should succeed")
	_expect(list_result.payload.get("count", 0) >= 4, "content list should include the framework-lab resources")

	var show_result := _run_content_cli([
		"show", "story", "story.lab.borrowed_umbrella", "--json",
	])
	_expect(show_result.exit_code == 0, "content show command should succeed")
	_expect(
		show_result.payload.get("item", {}).get("trigger_ids", []).size() == 6,
		"content show should expose story triggers"
	)

	var schema_result := _run_content_cli(["schema", "--json"])
	_expect(schema_result.exit_code == 0, "content schema command should succeed")
	_expect(schema_result.payload.get("schemas", []).size() == 3, "content schema should cover three types")

	_cleanup_cli_test_resources()
	var create_dialogue := _run_content_cli([
		"create", "dialogue", "dialogue.test.cli_template",
		"--path", CLI_TEMP_DIRECTORY + "/dialogue.tres",
		"--speaker", "Tester", "--text", "Placeholder", "--json",
	])
	var create_story := _run_content_cli([
		"create", "story", "story.test.cli_template",
		"--path", CLI_TEMP_DIRECTORY + "/story.tres",
		"--stages", "not_started,completed", "--json",
	])
	var create_map := _run_content_cli([
		"create", "map", "map.test.cli_template",
		"--path", CLI_TEMP_DIRECTORY + "/map.tres",
		"--scene", "res://scenes/maps/inn_hall.tscn",
		"--display-name", "Template", "--default-spawn", "start", "--json",
	])
	_expect(create_dialogue.exit_code == 0, "content create dialogue should succeed")
	_expect(create_story.exit_code == 0, "content create story should succeed")
	_expect(create_map.exit_code == 0, "content create map should succeed")
	var dialogue := load(CLI_TEMP_DIRECTORY + "/dialogue.tres") as DialogueDefinition
	var story := load(CLI_TEMP_DIRECTORY + "/story.tres") as StoryModule
	var map := load(CLI_TEMP_DIRECTORY + "/map.tres") as MapDefinition
	_expect(dialogue != null and dialogue.validate().is_empty(), "created dialogue should be valid")
	_expect(story != null and story.has_stage(&"completed"), "created story should preserve stages")
	_expect(map != null and map.scene != null, "created map should reference its scene")
	_cleanup_cli_test_resources()

	var missing_result := _run_content_cli(["show", "map", "map.test.missing", "--json"])
	_expect(missing_result.exit_code == 1, "content show should use a nonzero missing-content exit code")
	var missing_diagnostics: Array = missing_result.payload.get("diagnostics", [])
	_expect(not missing_diagnostics.is_empty(), "content show failure should include diagnostics")
	if not missing_diagnostics.is_empty():
		_expect(
			missing_diagnostics[0].get("code") == "content_not_found",
			"content show failure should have a structured diagnostic"
		)
	var duplicate_create := _run_content_cli([
		"create", "story", "story.lab.borrowed_umbrella",
		"--path", CLI_TEMP_DIRECTORY + "/duplicate.tres", "--json",
	])
	_expect(duplicate_create.exit_code == 1, "content create should reject duplicate IDs")
	var unsafe_create := _run_content_cli([
		"create", "story", "story.test.unsafe",
		"--path", "res://tests/../unsafe.tres", "--json",
	])
	_expect(unsafe_create.exit_code == 1, "content create should reject non-normalized paths")


func _run_content_cli(arguments: Array[String]) -> Dictionary:
	var command_arguments := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"-s",
		"res://tools/content_cli.gd",
		"--",
	])
	command_arguments.append_array(arguments)
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), command_arguments, output, true)
	var payload: Dictionary = {}
	for line: String in String("\n").join(output).split("\n"):
		if not line.begins_with("{") or not line.ends_with("}"):
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			payload = parsed
	return {"exit_code": exit_code, "payload": payload, "output": output}


func _cleanup_cli_test_resources() -> void:
	for file_name: String in ["dialogue.tres", "story.tres", "map.tres", "duplicate.tres"]:
		var path := CLI_TEMP_DIRECTORY.path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists("res://unsafe.tres"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://unsafe.tres"))
	var absolute_directory := ProjectSettings.globalize_path(CLI_TEMP_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)


func _test_scene_stack() -> void:
	var stack := GameSceneStack.new()
	get_root().add_child(stack)
	stack.configure(func() -> GameSceneContext:
		var context := GameSceneContext.new()
		context.scene_stack = stack
		return context
	)
	var rejections := PackedStringArray()
	stack.transition_rejected.connect(func(reason: String) -> void: rejections.append(reason))
	var base_scene := _pack_scene_stack_fixture()
	var modal_scene := _pack_scene_stack_fixture()
	_expect(stack.reset(base_scene, {"name": "base"}), "SceneStack reset should install a root scene")
	var base := stack.current_scene() as SceneStackTestScene
	_expect(base != null and base.enter_arguments.get("name") == "base", "reset should pass enter arguments")
	await process_frame
	var base_process_count := base.process_count
	_scene_stack_result_received = false
	_capture_scene_stack_result(stack, modal_scene)
	var modal := stack.current_scene() as SceneStackTestScene
	_expect(stack.scene_count() == 2 and modal != base, "push should add a modal scene")
	_expect(base.pause_count == 1, "push should pause the underlying scene")
	await process_frame
	_expect(base.process_count == base_process_count, "paused scenes should stop processing")

	if not InputMap.has_action(&"scene_stack_test_input"):
		InputMap.add_action(&"scene_stack_test_input")
	var input_event := InputEventAction.new()
	input_event.action = &"scene_stack_test_input"
	input_event.pressed = true
	Input.parse_input_event(input_event)
	await process_frame
	_expect(base.input_count == 0, "paused scenes should not receive unhandled input")
	_expect(modal.input_count == 1, "only the active scene should receive unhandled input")

	var pop_result := {"accepted": true}
	_expect(stack.pop(pop_result), "SceneStack pop should close a pushed scene")
	await process_frame
	_expect(stack.current_scene() == base, "pop should restore the underlying scene")
	_expect(base.resume_count == 1 and base.resume_result == pop_result, "pop should resume with its result")
	_expect(_scene_stack_result_received and _scene_stack_result == pop_result, "push caller should receive pop result")

	var replacement_scene := _pack_scene_stack_fixture()
	_expect(stack.replace(replacement_scene, {"name": "replacement"}), "replace should succeed")
	var replacement := stack.current_scene() as SceneStackTestScene
	_expect(base.exit_count == 1, "replace should exit the old scene")
	_expect(replacement.enter_arguments.get("name") == "replacement", "replace should pass arguments")

	var reentrant_scene := _pack_scene_stack_fixture()
	_scene_stack_result = "pending"
	_scene_stack_result_received = false
	_capture_scene_stack_result(stack, modal_scene)
	_expect(
		stack.reset(reentrant_scene, {"reentrant_scene": modal_scene}),
		"reset should install the requested scene"
	)
	await process_frame
	_expect(
		_scene_stack_result_received and _scene_stack_result == null,
		"reset should cancel a pending push result without leaving a waiter"
	)
	var reentrant := stack.current_scene() as SceneStackTestScene
	_expect(not reentrant.reentrant_replace_accepted, "SceneStack should reject reentrant transitions")
	_expect(stack.scene_count() == 1, "reentrant transition should not change the stack")
	_expect(not rejections.is_empty(), "reentrant transition should emit a diagnostic")
	_expect(not stack.pop(), "SceneStack should reject popping its root scene")
	InputMap.erase_action(&"scene_stack_test_input")
	stack.queue_free()
	await process_frame


func _capture_scene_stack_result(stack: GameSceneStack, scene: PackedScene) -> void:
	_scene_stack_result = await stack.push(scene, {"name": "modal"})
	_scene_stack_result_received = true


func _pack_scene_stack_fixture() -> PackedScene:
	var instance := SceneStackTestScene.new()
	var packed := PackedScene.new()
	var error := packed.pack(instance)
	instance.free()
	_expect(error == OK, "SceneStack fixture should pack")
	return packed


func _test_animated_sprite_scene_defaults() -> void:
	for scene_path: String in [
		"res://scenes/actors/player_character.tscn",
		"res://scenes/npcs/npc_character.tscn",
	]:
		var packed_scene := load(scene_path) as PackedScene
		var character := packed_scene.instantiate()
		var visual := character.get_node(^"Visual") as AnimatedSprite2D
		_expect(
			visual.sprite_frames != null,
			"AnimatedSprite2D should have editor-safe default frames: %s" % scene_path
		)
		character.free()


func _test_map_scene_content() -> void:
	var database := load("res://content/content_database.tres") as ContentDatabase
	var story := load("res://stories/lab/borrowed_umbrella.tres") as StoryModule
	var stories: Array[StoryModule] = [story]
	_expect(
		story.get_objective_text(&"looking_for_owner", &"map.lab.inn_hall")
		== "去雨院寻找蓑衣客",
		"story module should own its objective text"
	)
	var errors := database.build_index()
	errors.append_array(MapSceneValidator.new().validate(database, stories))
	_expect(errors.is_empty(), "map scene content should validate: %s" % "; ".join(errors))
	for map_id: StringName in [&"map.lab.inn_hall", &"map.lab.rain_courtyard"]:
		var definition := database.map(map_id)
		var map_scene := definition.scene.instantiate() as MapGameScene
		_expect(map_scene != null, "map scene should inherit the shared MapGameScene base: %s" % map_id)
		if map_scene != null:
			var ground := map_scene.get_node(^"GroundLayer") as TileMapLayer
			var details := map_scene.get_node(^"DetailLayer") as TileMapLayer
			_expect(ground.get_used_cells().size() == 150, "map should store 150 ground cells: %s" % map_id)
			_expect(details.get_used_cells().size() == 23, "map should store 23 detail cells: %s" % map_id)
			map_scene.free()
	_test_map_scene_validation_failures(database, stories)


func _test_map_scene_validation_failures(
	database: ContentDatabase,
	stories: Array[StoryModule]
) -> void:
	var source_hall := database.map(&"map.lab.inn_hall")
	var invalid_hall_scene := source_hall.scene.instantiate() as MapGameScene
	(invalid_hall_scene.get_node(^"GroundLayer") as TileMapLayer).clear()
	invalid_hall_scene.entry_trigger_id = &"missing_trigger"
	var innkeeper := invalid_hall_scene.get_node(^"YSortRoot/Innkeeper/Interactable") as Interactable
	var guest := invalid_hall_scene.get_node(^"YSortRoot/QuietGuest/Interactable") as Interactable
	guest.persistent_id = innkeeper.persistent_id
	var portal := invalid_hall_scene.get_node(^"YSortRoot/CourtyardDoor/Interactable") as Interactable
	portal.portal_target_spawn_id = &"missing_spawn"
	var invalid_packed_scene := PackedScene.new()
	var pack_error := invalid_packed_scene.pack(invalid_hall_scene)
	invalid_hall_scene.free()
	_expect(pack_error == OK, "invalid map fixture should pack in memory")
	if pack_error != OK:
		return
	var hall_definition := _copy_map_definition(source_hall)
	hall_definition.scene = invalid_packed_scene
	var courtyard_definition := _copy_map_definition(database.map(&"map.lab.rain_courtyard"))
	var invalid_database := ContentDatabase.new()
	invalid_database.maps.assign([hall_definition, courtyard_definition])
	var errors := invalid_database.build_index()
	errors.append_array(MapSceneValidator.new().validate(invalid_database, stories))
	_expect(_has_error(errors, "GroundLayer has no painted cells"), "validator should reject an empty TileMapLayer")
	_expect(_has_error(errors, "missing_trigger"), "validator should reject an unknown entry trigger")
	_expect(_has_error(errors, "repeated persistent ID"), "validator should reject repeated persistent IDs")
	_expect(_has_error(errors, "missing_spawn"), "validator should reject an unknown portal spawn")


func _copy_map_definition(source: MapDefinition) -> MapDefinition:
	var result := MapDefinition.new()
	result.id = source.id
	result.display_name = source.display_name
	result.description = source.description
	result.tags = source.tags.duplicate()
	result.scene = source.scene
	result.default_spawn_id = source.default_spawn_id
	result.music_source_id = source.music_source_id
	return result


func _has_error(errors: PackedStringArray, fragment: String) -> bool:
	for error: String in errors:
		if fragment in error:
			return true
	return false


func _test_scene_smoke() -> void:
	var root_scene := load("res://scenes/root/game_root.tscn") as PackedScene
	var game_root := root_scene.instantiate() as GameRoot
	get_root().add_child(game_root)
	await process_frame
	_expect(game_root.asset_library.using_generated_assets, "GameRoot should install only verified generated assets")
	_expect(game_root.scene_stack.current_scene() is TitleGameScene, "title scene should be first")
	game_root.start_new_game()
	await _drain_dialogue(game_root)
	var hall := game_root.scene_stack.current_scene() as MapGameScene
	_expect(hall != null and hall.map_id == &"map.lab.inn_hall", "new game should load the hall")
	if hall != null:
		_expect(hall.ground_layer.get_used_cells().size() == 150, "hall should load its stored TileMapLayer")
		_expect(hall.player.control_enabled, "player input should unlock after entry dialogue")
		hall.player.position = (hall.get_node("YSortRoot/Innkeeper") as Node2D).position
		hall._on_player_interact()
		await _drain_dialogue(game_root)
		_expect(
			game_root.game_run.story.get_stage(&"story.lab.borrowed_umbrella", &"")
			== &"looking_for_owner",
			"the real innkeeper binding should start the story"
		)
	var courtyard_definition := game_root.content_database.map(&"map.lab.rain_courtyard")
	game_root.travel_to(courtyard_definition, &"from_hall")
	await _drain_dialogue(game_root)
	var courtyard := game_root.scene_stack.current_scene() as MapGameScene
	_expect(
		courtyard != null and courtyard.map_id == &"map.lab.rain_courtyard",
		"travel should replace the active map"
	)
	if courtyard != null:
		_expect(courtyard.ground_layer.get_used_cells().size() == 150, "courtyard should load its stored TileMapLayer")
		courtyard.player.position = (courtyard.get_node("YSortRoot/Traveler") as Node2D).position
		courtyard._on_player_interact()
		await _drain_dialogue(game_root)
		_expect(
			game_root.game_run.story.get_stage(&"story.lab.borrowed_umbrella", &"")
			== &"owner_found",
			"the real traveler binding should identify the umbrella"
		)
		var umbrella := courtyard.get_node("YSortRoot/Umbrella") as Node2D
		courtyard.player.position = umbrella.position
		courtyard._on_player_interact()
		await _drain_dialogue(game_root)
		_expect(not umbrella.visible, "completed source entity should hide the umbrella immediately")
		_expect(
			game_root.game_run.world.is_completed(&"map.lab.rain_courtyard", &"old_umbrella"),
			"completed source entity should persist in WorldState"
		)
	var hall_definition := game_root.content_database.map(&"map.lab.inn_hall")
	game_root.travel_to(hall_definition, &"from_courtyard")
	await _drain_dialogue(game_root)
	hall = game_root.scene_stack.current_scene() as MapGameScene
	if hall != null:
		hall.player.position = (hall.get_node("YSortRoot/Innkeeper") as Node2D).position
		hall._on_player_interact()
		await _drain_dialogue(game_root)
	_expect(
		game_root.game_run.story.get_stage(&"story.lab.borrowed_umbrella", &"") == &"completed",
		"the real two-map story should reach its completed stage"
	)
	await _test_herbal_room_scene(game_root)
	await _test_bridge_battle_scene(game_root)
	var save_error := game_root.save_service.save_run(game_root.game_run, TEST_SAVE)
	_expect(save_error == OK, "SaveService should write an atomic test save")
	var loaded := game_root.save_service.load_run(TEST_SAVE)
	_expect(loaded != null, "SaveService should load the test save")
	if loaded != null:
		_expect(
			loaded.story.get_stage(&"story.lab.borrowed_umbrella", &"") == &"completed",
			"SaveService should preserve story progress"
		)
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	game_root.queue_free()
	await process_frame


func _test_herbal_room_scene(game_root: GameRoot) -> void:
	var herbal_definition := game_root.content_database.map(&"map.lab.herbal_room")
	game_root.travel_to(herbal_definition, &"from_hall")
	await process_frame
	await process_frame
	var herbal_room := game_root.scene_stack.current_scene() as MapGameScene
	_expect(
		herbal_room != null and herbal_room.map_id == &"map.lab.herbal_room",
		"G6 content should enter the herbal room"
	)
	if herbal_room == null:
		return
	var herb := game_root.content_database.item(&"item.lab.healing_herb")
	var draught := game_root.content_database.item(&"item.lab.spirit_draught")
	var chest := herbal_room.get_node("YSortRoot/MedicineChest") as Node2D
	herbal_room.player.position = chest.position
	await herbal_room._on_player_interact()
	_expect(game_root.game_run.inventory.quantity(herb.id) == 2, "TreasureChestEvent should grant two herbs")
	_expect(not chest.visible, "completed treasure source should hide immediately")

	var pickup := herbal_room.get_node("YSortRoot/SpiritDraught") as Node2D
	herbal_room.player.position = pickup.position
	await herbal_room._on_player_interact()
	_expect(game_root.game_run.inventory.quantity(draught.id) == 1, "ItemPickupEvent should grant the draught")
	_expect(not pickup.visible, "completed pickup source should hide immediately")

	var apothecary := herbal_room.get_node("YSortRoot/Apothecary") as Node2D
	herbal_room.player.position = apothecary.position
	herbal_room._on_player_interact()
	await process_frame
	var shop_scene := game_root.scene_stack.current_scene() as ShopGameScene
	_expect(shop_scene != null, "ShopEvent should push ShopGameScene")
	if shop_scene != null:
		shop_scene._buy_at(0)
		_expect(game_root.game_run.inventory.quantity(herb.id) == 3, "shop should add the purchased herb")
		_expect(game_root.game_run.economy.money == 28, "shop should deduct the configured price")
		game_root.scene_stack.pop(shop_scene._last_result)
		await process_frame
	_expect(game_root.scene_stack.current_scene() == herbal_room, "shop pop should restore the same map")

	var leader := game_root.game_run.party.leader()
	leader.hp = 50
	game_root.scene_stack.push(game_root.menu_scene)
	await process_frame
	var menu := game_root.scene_stack.current_scene() as MenuGameScene
	_expect(menu != null, "menu input path should push MenuGameScene")
	if menu != null:
		menu._use_item_at(0)
		_expect(leader.hp == 85, "menu item use should apply HealEffect to the leader")
		_expect(game_root.game_run.inventory.quantity(herb.id) == 2, "menu use should consume one herb")
		game_root.scene_stack.pop()
		await process_frame
	_expect(game_root.scene_stack.current_scene() == herbal_room, "menu pop should restore the herbal room")


func _test_bridge_battle_scene(game_root: GameRoot) -> void:
	var bridge_definition := game_root.content_database.map(&"map.lab.broken_bridge")
	game_root.travel_to(bridge_definition, &"from_courtyard")
	await process_frame
	await process_frame
	var bridge := game_root.scene_stack.current_scene() as MapGameScene
	_expect(bridge != null and bridge.map_id == &"map.lab.broken_bridge", "G7 content should enter the bridge")
	if bridge == null:
		return
	var bandit := bridge.get_node("YSortRoot/Bandit") as Node2D
	bridge.player.position = bandit.position
	bridge._on_player_interact()
	await process_frame
	var battle := game_root.scene_stack.current_scene() as BattleGameScene
	_expect(battle != null, "bridge StoryModule should push BattleGameScene")
	if battle != null:
		await battle._execute_command(BattleSession.Command.ESCAPE)
		await _wait_for_story_settle(game_root)
	_expect(game_root.scene_stack.current_scene() == bridge, "Escaped should restore the same bridge map")
	_expect(bandit.visible, "Escaped should preserve the bandit source")

	game_root.game_run.party.leader().hp = 1
	bridge._on_player_interact()
	await process_frame
	battle = game_root.scene_stack.current_scene() as BattleGameScene
	_expect(battle != null, "preserved bandit should allow another battle")
	if battle != null:
		await battle._execute_command(BattleSession.Command.ATTACK)
		await _wait_for_story_settle(game_root)
	var safe_map := game_root.scene_stack.current_scene() as MapGameScene
	_expect(
		safe_map != null and safe_map.map_id == &"map.lab.rain_courtyard",
		"Defeat should restore party and travel to the configured safe map"
	)
	_expect(
		game_root.game_run.party.leader().hp
		== game_root.content_database.actor(&"actor.li_xiaoyao").base_max_hp,
		"Defeat flow should restore party before returning control"
	)

	game_root.travel_to(bridge_definition, &"from_courtyard")
	await process_frame
	await process_frame
	bridge = game_root.scene_stack.current_scene() as MapGameScene
	bandit = bridge.get_node("YSortRoot/Bandit") as Node2D
	bridge.player.position = bandit.position
	bridge._on_player_interact()
	await process_frame
	battle = game_root.scene_stack.current_scene() as BattleGameScene
	_expect(battle != null, "Defeat should also preserve the bandit source")
	if battle != null:
		battle.session.enemy.hp = 1
		await battle._execute_command(BattleSession.Command.ATTACK)
		await _wait_for_story_settle(game_root)
	_expect(game_root.scene_stack.current_scene() == bridge, "Victory should pop back to the bridge")
	_expect(not bandit.visible, "Victory should complete and hide the bandit source")
	_expect(
		game_root.game_run.world.is_completed(&"map.lab.broken_bridge", &"bridge_bandit"),
		"Victory should persist the completed battle source"
	)


func _wait_for_story_settle(game_root: GameRoot) -> void:
	for _frame: int in range(30):
		await process_frame
		if not game_root.story_director.is_busy() and not game_root.scene_stack.is_transitioning():
			return
	_expect(false, "story/scene stack did not settle within 30 frames")


func _drain_dialogue(game_root: GameRoot) -> void:
	await process_frame
	await process_frame
	for _frame: int in range(30):
		await process_frame
		if game_root.dialogue_layer.is_active():
			await process_frame
			game_root.dialogue_layer.advance_requested.emit()
		if not game_root.story_director.is_busy() and not game_root.dialogue_layer.is_active():
			return
	_expect(false, "dialogue/story call did not settle within 30 frames")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
