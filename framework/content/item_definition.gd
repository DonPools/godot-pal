@tool
class_name ItemDefinition
extends ContentDefinition

enum Category {
	CONSUMABLE,
	EQUIPMENT,
	KEY_ITEM,
	MATERIAL,
}

@export var category: Category = Category.CONSUMABLE
@export var icon: Texture2D
@export_range(0, 999999) var price: int = 0
@export_range(1, 99) var max_stack: int = 9
@export var can_discard: bool = true
@export var can_sell: bool = true
@export var usable_in_field: bool = false
@export var usable_in_battle: bool = false
@export var effects: Array[GameEffect] = []


## Declared usability alone is insufficient: only consumables with effects can execute.
func can_be_used_in_field() -> bool:
	return (
		category == Category.CONSUMABLE
		and usable_in_field
		and not effects.is_empty()
	)


## Mirrors field usability for the battle transaction and loadout boundary.
func can_be_used_in_battle() -> bool:
	return (
		category == Category.CONSUMABLE
		and usable_in_battle
		and not effects.is_empty()
	)
