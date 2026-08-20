extends SceneTree

const VALIDATOR := preload("res://game/testing/r9_field_test_validator.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2 or arguments[0] != "validate":
		_finish(
			1,
			{
				"ok": false,
				"contract_version": R9FieldTestValidator.CONTRACT_VERSION,
				"diagnostics": [{
					"code": "usage",
					"field": "command",
					"message": "usage: validate <field-test-results.json>",
				}],
			}
		)
		return
	var path := arguments[1]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_finish(
			1,
			{
				"ok": false,
				"contract_version": R9FieldTestValidator.CONTRACT_VERSION,
				"diagnostics": [{
					"code": "results_read_failed",
					"field": path,
					"message": "results file cannot be read",
				}],
			}
		)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_finish(
			1,
			{
				"ok": false,
				"contract_version": R9FieldTestValidator.CONTRACT_VERSION,
				"diagnostics": [{
					"code": "results_json_invalid",
					"field": path,
					"message": "results file must contain one JSON object",
				}],
			}
		)
		return
	var result := (VALIDATOR.new() as R9FieldTestValidator).validate(parsed as Dictionary)
	_finish(0 if bool(result.get("ok", false)) else 1, result)


func _finish(exit_code: int, result: Dictionary) -> void:
	print(JSON.stringify(result))
	quit(exit_code)
