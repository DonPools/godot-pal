@tool
class_name ShopEntry
extends Resource

@export var item: ItemDefinition
@export var price_override: int = -1


func buy_price() -> int:
	return price_override if price_override >= 0 else item.price if item != null else 0
