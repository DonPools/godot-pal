class_name CultivationTransaction
extends RefCounted


static func breakthrough(
	game_run: GameRun,
	foundation: DaoFoundationDefinition,
	catalyst: ItemDefinition,
	database: ContentDatabase
) -> CultivationResult:
	if game_run == null or database == null:
		return CultivationResult.new()
	var actor_state := game_run.party.leader()
	var checked := CultivationRules.check_breakthrough(actor_state, foundation, database)
	if not checked.succeeded():
		return checked
	if catalyst == null or game_run.inventory.quantity(catalyst.id) <= 0:
		checked.outcome = CultivationResult.Outcome.CATALYST_REQUIRED
		return checked
	var trial := InventoryState.new()
	if not trial.restore(game_run.inventory.to_dictionary()):
		checked.outcome = CultivationResult.Outcome.CATALYST_REQUIRED
		return checked
	if not trial.remove_item(catalyst, 1).succeeded():
		checked.outcome = CultivationResult.Outcome.CATALYST_REQUIRED
		return checked
	var result := CultivationRules.breakthrough(actor_state, foundation, database)
	if not result.succeeded():
		return result
	game_run.inventory.restore(trial.to_dictionary())
	var definition := database.actor(actor_state.definition_id)
	actor_state.hp = CultivationRules.max_hp(definition, actor_state, database)
	actor_state.mp = CultivationRules.max_mp(definition, actor_state, database)
	return result
