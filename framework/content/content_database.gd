@tool
class_name ContentDatabase
extends Resource

@export var realms: Array[CultivationRealmDefinition] = []
@export var foundations: Array[DaoFoundationDefinition] = []
@export var actors: Array[ActorDefinition] = []
@export var npcs: Array[NpcDefinition] = []
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

var _realms_by_id: Dictionary[StringName, CultivationRealmDefinition] = {}
var _foundations_by_id: Dictionary[StringName, DaoFoundationDefinition] = {}
var _actors_by_id: Dictionary[StringName, ActorDefinition] = {}
var _npcs_by_id: Dictionary[StringName, NpcDefinition] = {}
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
	for definition: CultivationRealmDefinition in realms:
		if definition == null:
			errors.append("ContentDatabase contains an empty cultivation realm reference")
		elif definition.id.is_empty():
			errors.append("CultivationRealmDefinition has an empty id")
		elif _realms_by_id.has(definition.id):
			errors.append("Duplicate realm id: %s" % definition.id)
		else:
			_realms_by_id[definition.id] = definition
			ContentDefinitionValidator.validate_realm(definition, errors)
	for definition: DaoFoundationDefinition in foundations:
		if definition == null:
			errors.append("ContentDatabase contains an empty dao foundation reference")
		elif definition.id.is_empty():
			errors.append("DaoFoundationDefinition has an empty id")
		elif _foundations_by_id.has(definition.id):
			errors.append("Duplicate foundation id: %s" % definition.id)
		else:
			_foundations_by_id[definition.id] = definition
			ContentDefinitionValidator.validate_foundation(definition, errors)
	for definition: ActorDefinition in actors:
		if definition == null:
			errors.append("ContentDatabase contains an empty actor reference")
		elif definition.id.is_empty():
			errors.append("ActorDefinition has an empty id")
		elif _actors_by_id.has(definition.id):
			errors.append("Duplicate actor id: %s" % definition.id)
		else:
			_actors_by_id[definition.id] = definition
			ContentDefinitionValidator.validate_actor(definition, errors)
	for definition: NpcDefinition in npcs:
		if definition == null:
			errors.append("ContentDatabase contains an empty NPC reference")
		elif definition.id.is_empty():
			errors.append("NpcDefinition has an empty id")
		elif _npcs_by_id.has(definition.id):
			errors.append("Duplicate NPC id: %s" % definition.id)
		else:
			_npcs_by_id[definition.id] = definition
			ContentDefinitionValidator.validate_npc(definition, errors)
	for definition: ItemDefinition in items:
		if definition == null:
			errors.append("ContentDatabase contains an empty item reference")
		elif definition.id.is_empty():
			errors.append("ItemDefinition has an empty id")
		elif _items_by_id.has(definition.id):
			errors.append("Duplicate item id: %s" % definition.id)
		else:
			_items_by_id[definition.id] = definition
			ContentDefinitionValidator.validate_item(definition, errors)
	for definition: SkillDefinition in skills:
		if definition == null:
			errors.append("ContentDatabase contains an empty skill reference")
		elif definition.id.is_empty():
			errors.append("SkillDefinition has an empty id")
		elif _skills_by_id.has(definition.id):
			errors.append("Duplicate skill id: %s" % definition.id)
		else:
			_skills_by_id[definition.id] = definition
			ContentDefinitionValidator.validate_skill(definition, errors)
	for definition: StatusDefinition in statuses:
		if definition == null:
			errors.append("ContentDatabase contains an empty status reference")
		elif definition.id.is_empty():
			errors.append("StatusDefinition has an empty id")
		elif _statuses_by_id.has(definition.id):
			errors.append("Duplicate status id: %s" % definition.id)
		else:
			_statuses_by_id[definition.id] = definition
			ContentDefinitionValidator.validate_status(definition, errors)
	for definition: EnemyDefinition in enemies:
		if definition == null:
			errors.append("ContentDatabase contains an empty enemy reference")
		elif definition.id.is_empty():
			errors.append("EnemyDefinition has an empty id")
		elif _enemies_by_id.has(definition.id):
			errors.append("Duplicate enemy id: %s" % definition.id)
		else:
			_enemies_by_id[definition.id] = definition
			ContentDefinitionValidator.validate_enemy(definition, errors)
	for definition: BattleEncounter in encounters:
		if definition == null:
			errors.append("ContentDatabase contains an empty encounter reference")
		elif definition.id.is_empty():
			errors.append("BattleEncounter has an empty id")
		elif _encounters_by_id.has(definition.id):
			errors.append("Duplicate encounter id: %s" % definition.id)
		else:
			_encounters_by_id[definition.id] = definition
			ContentDefinitionValidator.validate_encounter(definition, errors)
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
	errors.append_array(ContentReferenceValidator.validate(self))
	return errors


func actor(id: StringName) -> ActorDefinition:
	return _actors_by_id.get(id)


func realm(id: StringName) -> CultivationRealmDefinition:
	return _realms_by_id.get(id)


func foundation(id: StringName) -> DaoFoundationDefinition:
	return _foundations_by_id.get(id)


func npc(id: StringName) -> NpcDefinition:
	return _npcs_by_id.get(id)


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


func has_realm(id: StringName) -> bool:
	return _realms_by_id.has(id)


func has_foundation(id: StringName) -> bool:
	return _foundations_by_id.has(id)


func has_npc(id: StringName) -> bool:
	return _npcs_by_id.has(id)


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
	return GameRunContentValidator.validate(game_run, self)


func _clear_indexes() -> void:
	_realms_by_id.clear()
	_foundations_by_id.clear()
	_actors_by_id.clear()
	_npcs_by_id.clear()
	_items_by_id.clear()
	_skills_by_id.clear()
	_statuses_by_id.clear()
	_enemies_by_id.clear()
	_encounters_by_id.clear()
	_shops_by_id.clear()
	_maps_by_id.clear()
