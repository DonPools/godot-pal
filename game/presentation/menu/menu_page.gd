class_name MenuPage
extends Control

signal hint_requested(message: String)
signal content_changed

var _database: ContentDatabase
var _game_run: GameRun


func configure(database: ContentDatabase, game_run: GameRun) -> void:
	_database = database
	_game_run = game_run


func refresh_text() -> void:
	pass


func refresh() -> void:
	pass


func initial_focus_control() -> Control:
	return null


func has_open_modal() -> bool:
	return false


func close_modal() -> void:
	pass


func _leader() -> ActorState:
	return _game_run.party.leader() if _game_run != null else null


func _leader_definition() -> ActorDefinition:
	var leader := _leader()
	return (
		_database.actor(leader.definition_id)
		if leader != null and _database != null
		else null
	)


func _request_equipment_result_hint(
	result: EquipmentResult,
	equipment: ItemDefinition
) -> void:
	match result.outcome:
		EquipmentResult.Outcome.EQUIPPED:
			hint_requested.emit(tr("UI_MENU_EQUIPPED") % equipment.display_name)
		EquipmentResult.Outcome.ALREADY_EQUIPPED:
			hint_requested.emit(
				tr("UI_MENU_ALREADY_EQUIPPED") % equipment.display_name
			)
		EquipmentResult.Outcome.INVENTORY_REJECTED:
			hint_requested.emit(tr("UI_MENU_INVENTORY_REJECTED"))
		EquipmentResult.Outcome.SLOT_NOT_ALLOWED:
			hint_requested.emit(tr("UI_MENU_SLOT_NOT_ALLOWED"))
		_:
			hint_requested.emit(tr("UI_MENU_EQUIP_FAILED") % equipment.display_name)
