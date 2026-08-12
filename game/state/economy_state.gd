class_name EconomyState
extends RefCounted

var money: int = 0


func can_afford(amount: int) -> bool:
	return amount >= 0 and money >= amount


func try_spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	money -= amount
	return true


func add_money(amount: int) -> void:
	money = maxi(money + amount, 0)


func to_dictionary() -> Dictionary:
	return {"money": money}


func restore(data: Dictionary) -> bool:
	var restored_money := int(data.get("money", -1))
	if restored_money < 0:
		return false
	money = restored_money
	return true
