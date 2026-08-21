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
@export var usable_in_field: bool = true
@export var usable_in_battle: bool = true
@export var effects: Array[GameEffect] = []
