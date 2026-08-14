@tool
class_name ContentDatabase
extends Resource

@export var actors: Array[ActorDefinition] = []
@export var items: Array[ItemDefinition] = []
@export var skills: Array[SkillDefinition] = []
@export var statuses: Array[StatusDefinition] = []
@export var enemies: Array[EnemyDefinition] = []
@export var encounters: Array[BattleEncounter] = []
@export var shops: Array[ShopDefinition] = []
@export var maps: Array[MapDefinition] = []
@export var story_directories: PackedStringArray = []
@export var starting_party: Array[ActorDefinition] = []
@export_range(0, 999999) var starting_money: int = 40

var _actors_by_id: Dictionary[StringName, ActorDefinition] = {}
var _items_by_id: Dictionary[StringName, ItemDefinition] = {}
var _skills_by_id: Dictionary[StringName, SkillDefinition] = {}
var _statuses_by_id: Dictionary[StringName, StatusDefinition] = {}
var _enemies_by_id: Dictionary[StringName, EnemyDefinition] = {}
var _encounters_by_id: Dictionary[StringName, BattleEncounter] = {}
var _shops_by_id: Dictionary[StringName, ShopDefinition] = {}
var _maps_by_id: Dictionary[StringName, MapDefinition] = {}


func build_index() -> PackedStringArray:
	_clear_indexes()
	var errors := PackedStringArray()
	for definition: ActorDefinition in actors:
		if definition == null:
			errors.append("ContentDatabase contains an empty actor reference")
		elif definition.id.is_empty():
			errors.append("ActorDefinition has an empty id")
		elif _actors_by_id.has(definition.id):
			errors.append("Duplicate actor id: %s" % definition.id)
		else:
			_actors_by_id[definition.id] = definition
			if definition.base_max_hp < 1 or definition.base_max_mp < 0 or definition.initial_level < 1:
				errors.append("Actor %s has invalid HP, MP, or initial level" % definition.id)
	for definition: ItemDefinition in items:
		if definition == null:
			errors.append("ContentDatabase contains an empty item reference")
		elif definition.id.is_empty():
			errors.append("ItemDefinition has an empty id")
		elif _items_by_id.has(definition.id):
			errors.append("Duplicate item id: %s" % definition.id)
		else:
			_items_by_id[definition.id] = definition
			if (
				definition.price < 0
				or definition.max_stack < 1
				or int(definition.category) not in ItemDefinition.Category.values()
			):
				errors.append("Item %s has invalid price or max_stack" % definition.id)
			if definition is EquipmentDefinition and (definition as EquipmentDefinition).slot.is_empty():
				errors.append("Equipment %s has an empty slot" % definition.id)
	for definition: SkillDefinition in skills:
		if definition == null:
			errors.append("ContentDatabase contains an empty skill reference")
		elif definition.id.is_empty():
			errors.append("SkillDefinition has an empty id")
		elif _skills_by_id.has(definition.id):
			errors.append("Duplicate skill id: %s" % definition.id)
		else:
			_skills_by_id[definition.id] = definition
			if definition.mp_cost < 0:
				errors.append("Skill %s has invalid mp_cost" % definition.id)
	for definition: StatusDefinition in statuses:
		if definition == null:
			errors.append("ContentDatabase contains an empty status reference")
		elif definition.id.is_empty():
			errors.append("StatusDefinition has an empty id")
		elif _statuses_by_id.has(definition.id):
			errors.append("Duplicate status id: %s" % definition.id)
		else:
			_statuses_by_id[definition.id] = definition
			if definition.duration_rounds < 1 or definition.periodic_damage < 0:
				errors.append("Status %s has invalid duration or periodic damage" % definition.id)
	for definition: EnemyDefinition in enemies:
		if definition == null:
			errors.append("ContentDatabase contains an empty enemy reference")
		elif definition.id.is_empty():
			errors.append("EnemyDefinition has an empty id")
		elif _enemies_by_id.has(definition.id):
			errors.append("Duplicate enemy id: %s" % definition.id)
		else:
			_enemies_by_id[definition.id] = definition
			if (
				definition.max_hp < 1
				or definition.attack < 0
				or definition.money_reward < 0
				or definition.drop_quantity < 0
			):
				errors.append("Enemy %s has invalid combat values" % definition.id)
	for definition: BattleEncounter in encounters:
		if definition == null:
			errors.append("ContentDatabase contains an empty encounter reference")
		elif definition.id.is_empty():
			errors.append("BattleEncounter has an empty id")
		elif _encounters_by_id.has(definition.id):
			errors.append("Duplicate encounter id: %s" % definition.id)
		else:
			_encounters_by_id[definition.id] = definition
	for definition: ShopDefinition in shops:
		if definition == null:
			errors.append("ContentDatabase contains an empty shop reference")
		elif definition.id.is_empty():
			errors.append("ShopDefinition has an empty id")
		elif _shops_by_id.has(definition.id):
			errors.append("Duplicate shop id: %s" % definition.id)
		else:
			_shops_by_id[definition.id] = definition
	for definition: MapDefinition in maps:
		if definition == null:
			errors.append("ContentDatabase contains an empty map reference")
		elif definition.id.is_empty():
			errors.append("MapDefinition has an empty id")
		elif _maps_by_id.has(definition.id):
			errors.append("Duplicate map id: %s" % definition.id)
		elif definition.scene == null:
			errors.append("Map %s has no scene" % definition.id)
		else:
			_maps_by_id[definition.id] = definition
	_validate_references(errors)
	return errors


func actor(id: StringName) -> ActorDefinition:
	return _actors_by_id.get(id)


func item(id: StringName) -> ItemDefinition:
	return _items_by_id.get(id)


func skill(id: StringName) -> SkillDefinition:
	return _skills_by_id.get(id)


func status(id: StringName) -> StatusDefinition:
	return _statuses_by_id.get(id)


func enemy(id: StringName) -> EnemyDefinition:
	return _enemies_by_id.get(id)


func encounter(id: StringName) -> BattleEncounter:
	return _encounters_by_id.get(id)


func shop(id: StringName) -> ShopDefinition:
	return _shops_by_id.get(id)


func map(id: StringName) -> MapDefinition:
	return _maps_by_id.get(id)


func has_actor(id: StringName) -> bool:
	return _actors_by_id.has(id)


func has_item(id: StringName) -> bool:
	return _items_by_id.has(id)


func has_skill(id: StringName) -> bool:
	return _skills_by_id.has(id)


func has_status(id: StringName) -> bool:
	return _statuses_by_id.has(id)


func has_enemy(id: StringName) -> bool:
	return _enemies_by_id.has(id)


func has_encounter(id: StringName) -> bool:
	return _encounters_by_id.has(id)


func has_shop(id: StringName) -> bool:
	return _shops_by_id.has(id)


func has_map(id: StringName) -> bool:
	return _maps_by_id.has(id)


func validate_game_run(game_run: GameRun) -> PackedStringArray:
	var errors := PackedStringArray()
	if game_run == null:
		errors.append("GameRun is empty")
		return errors
	if not has_map(game_run.location.map_id):
		errors.append("GameRun references unknown map %s" % game_run.location.map_id)
	if game_run.party.members.is_empty():
		errors.append("GameRun party is empty")
	for actor_state: ActorState in game_run.party.members:
		var actor_definition := actor(actor_state.definition_id)
		if actor_definition == null:
			errors.append("GameRun references unknown actor %s" % actor_state.definition_id)
			continue
		if actor_state.hp > actor_definition.base_max_hp or actor_state.mp > actor_definition.base_max_mp:
			errors.append("ActorState %s exceeds its HP/MP limits" % actor_state.definition_id)
		for slot: StringName in actor_state.equipment:
			var equipment := item(actor_state.equipment[slot]) as EquipmentDefinition
			if equipment == null or equipment.slot != slot:
				errors.append(
					"ActorState %s has invalid equipment %s in slot %s"
					% [actor_state.definition_id, actor_state.equipment[slot], slot]
				)
		for skill_id: StringName in actor_state.skill_ids:
			if not has_skill(skill_id):
				errors.append("ActorState %s references unknown skill %s" % [actor_state.definition_id, skill_id])
	for item_id: StringName in game_run.inventory.item_ids():
		var definition := item(item_id)
		if definition == null:
			errors.append("InventoryState references unknown item %s" % item_id)
		elif game_run.inventory.quantity(item_id) > definition.max_stack:
			errors.append("InventoryState item %s exceeds max_stack" % item_id)
	return errors


func _clear_indexes() -> void:
	_actors_by_id.clear()
	_items_by_id.clear()
	_skills_by_id.clear()
	_statuses_by_id.clear()
	_enemies_by_id.clear()
	_encounters_by_id.clear()
	_shops_by_id.clear()
	_maps_by_id.clear()


func _validate_references(errors: PackedStringArray) -> void:
	if starting_party.is_empty():
		errors.append("ContentDatabase starting_party is empty")
	var starting_ids: Dictionary[StringName, bool] = {}
	for definition: ActorDefinition in starting_party:
		if definition == null or not _actors_by_id.has(definition.id):
			errors.append("ContentDatabase starting_party references an unregistered actor")
		elif starting_ids.has(definition.id):
			errors.append("ContentDatabase starting_party repeats actor %s" % definition.id)
		else:
			starting_ids[definition.id] = true
	for definition: ActorDefinition in actors:
		if definition == null:
			continue
		for equipment: EquipmentDefinition in definition.initial_equipment:
			if equipment == null or not _items_by_id.has(equipment.id):
				errors.append("Actor %s references unregistered initial equipment" % definition.id)
		for skill_definition: SkillDefinition in definition.initial_skills:
			if skill_definition == null or not _skills_by_id.has(skill_definition.id):
				errors.append("Actor %s references unregistered initial skill" % definition.id)
	for definition: ItemDefinition in items:
		if definition == null:
			continue
		if definition.max_stack < 1:
			errors.append("Item %s has invalid max_stack" % definition.id)
		for effect: GameEffect in definition.effects:
			if effect == null or effect.id.is_empty():
				errors.append("Item %s contains an invalid GameEffect" % definition.id)
	for definition: SkillDefinition in skills:
		if definition == null:
			continue
		for effect: GameEffect in definition.effects:
			if effect == null or effect.id.is_empty():
					errors.append("Skill %s contains an invalid GameEffect" % definition.id)
	for definition: EnemyDefinition in enemies:
		if definition != null:
			if definition.strategy == null:
				errors.append("Enemy %s has no EnemyStrategy" % definition.id)
			if definition.drop_item != null and not has_item(definition.drop_item.id):
				errors.append("Enemy %s references an unregistered drop item" % definition.id)
			if definition.strategy is ChillStrikeStrategy:
				var chill_strategy := definition.strategy as ChillStrikeStrategy
				if chill_strategy.status == null or not has_status(chill_strategy.status.id):
					errors.append("Enemy %s references an unregistered status" % definition.id)
	for definition: BattleEncounter in encounters:
		if definition == null:
			continue
		if definition.enemies.is_empty():
			errors.append("Encounter %s has no enemies" % definition.id)
		var instance_ids: Dictionary[StringName, bool] = {}
		for entry: EncounterEnemy in definition.enemies:
			if entry == null or entry.enemy == null or not has_enemy(entry.enemy.id):
				errors.append("Encounter %s contains an invalid enemy" % definition.id)
			elif entry.instance_id.is_empty() or instance_ids.has(entry.instance_id):
				errors.append("Encounter %s has an empty or repeated enemy instance ID" % definition.id)
			else:
				instance_ids[entry.instance_id] = true
	for definition: ShopDefinition in shops:
		if definition == null:
			continue
		var shop_items: Dictionary[StringName, bool] = {}
		for entry: ShopEntry in definition.entries:
			if entry == null or entry.item == null or not _items_by_id.has(entry.item.id):
				errors.append("Shop %s contains an invalid item entry" % definition.id)
			elif shop_items.has(entry.item.id):
				errors.append("Shop %s repeats item %s" % [definition.id, entry.item.id])
			else:
				shop_items[entry.item.id] = true
				if entry.buy_price() < 0:
					errors.append("Shop %s item %s has an invalid price" % [definition.id, entry.item.id])
