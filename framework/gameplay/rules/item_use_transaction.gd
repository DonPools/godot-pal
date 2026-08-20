class_name ItemUseTransaction
extends RefCounted


static func use_on_actor(
	game_run: GameRun,
	item: ItemDefinition,
	target: ActorState,
	target_definition: ActorDefinition,
	database: ContentDatabase = null
) -> ItemUseResult:
	var result := ItemUseResult.new()
	result.item_id = item.id if item != null else &""
	if (
		game_run == null
		or item == null
		or target == null
		or target_definition == null
		or not item.usable_in_field
		or item.effects.is_empty()
	):
		return result
	if game_run.inventory.quantity(item.id) <= 0:
		result.outcome = ItemUseResult.Outcome.NO_ITEM
		return result
	var snapshot_hp := target.hp
	var snapshot_mp := target.mp
	var changed := 0
	var context := EffectContext.create(
		item.id,
		target,
		target_definition,
		CultivationRules.max_hp(target_definition, target, database),
		CultivationRules.max_mp(target_definition, target, database)
	)
	for effect: GameEffect in item.effects:
		if effect != null:
			changed += effect.apply(context).changed_amount
	if changed <= 0:
		target.hp = snapshot_hp
		target.mp = snapshot_mp
		result.outcome = ItemUseResult.Outcome.NO_EFFECT
		return result
	var removal := game_run.inventory.remove_item(item, 1)
	if not removal.succeeded():
		target.hp = snapshot_hp
		target.mp = snapshot_mp
		result.outcome = ItemUseResult.Outcome.NO_ITEM
		return result
	result.outcome = ItemUseResult.Outcome.USED
	result.changed_amount = changed
	return result
