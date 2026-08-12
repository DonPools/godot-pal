class_name EnemyDefinition
extends ContentDefinition

@export_range(1, 9999) var max_hp: int = 30
@export_range(0, 999) var attack: int = 8
@export_range(0, 99999) var money_reward: int = 0
@export var drop_item: ItemDefinition
@export_range(0, 99) var drop_quantity: int = 0
@export var sprite_source_id: int = 207
@export var strategy: EnemyStrategy
