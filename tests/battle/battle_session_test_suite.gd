class_name BattleSessionTestSuite
extends RefCounted


func run() -> PackedStringArray:
	var failures := PackedStringArray()
	failures.append_array(BattleValidationTestSuite.new().run())
	failures.append_array(BattleActionTestSuite.new().run())
	failures.append_array(BattleOutcomeTestSuite.new().run())
	return failures
