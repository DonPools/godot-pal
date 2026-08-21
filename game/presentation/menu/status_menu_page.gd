class_name StatusMenuPage
extends MenuPage

@onready var summary: Label = $Summary


func refresh() -> void:
	var leader := _leader()
	var definition := _leader_definition()
	if leader == null or definition == null:
		summary.text = tr("UI_MENU_PARTY_EMPTY")
		return
	var realm := _database.realm(leader.realm_id)
	var foundation := _database.foundation(leader.foundation_id)
	var equipment := _database.item(leader.equipment.get(&"weapon", &""))
	summary.text = tr("UI_MENU_STATUS_FORMAT") % [
		definition.display_name,
		realm.display_name if realm != null else String(leader.realm_id),
		leader.realm_layer,
		leader.cultivation_points,
		foundation.display_name if foundation != null else tr("UI_MENU_NONE"),
		leader.hp,
		CultivationRules.max_hp(definition, leader, _database),
		leader.mp,
		CultivationRules.max_mp(definition, leader, _database),
		CultivationRules.attack(definition, leader, _database),
		equipment.display_name if equipment != null else tr("UI_MENU_NONE"),
		_game_run.economy.money,
	]
