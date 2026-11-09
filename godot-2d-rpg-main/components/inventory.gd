@icon("res://icons/Inventory.svg")
class_name Inventory
extends CanvasLayer

@export var action_trigger = "inventory"

@onready var item_list: ItemList = $MarginContainer/ItemList

var is_open := false
var items: Array[ContentItem] = [] ## The items in this inventory.

signal equip_weapon(weapon: DataWeapon)

func _ready() -> void:
	visible = is_open

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(action_trigger):
		toggle_inventory()

func toggle_inventory():
	is_open = !is_open
	visible = is_open
	get_tree().paused = is_open
	if is_open:
		_update_item_list()
		item_list.grab_focus()
	else:
		item_list.clear()

##Get the index of the item in inventory, -1 if not found.
func is_item_in_inventory(item_name: String, quantity := 1) -> int:
	var item_index := -1
	for i in items.size():
		var content: ContentItem = items[i]
		if content.item.resource_name == item_name and content.quantity >= quantity:
			item_index = i
	return item_index

##Adds an item to the inventory.
func add_item(item: DataItem, quantity: int):
	var item_index = is_item_in_inventory(item.resource_name)
	if item_index >= 0:
		items[item_index].quantity += quantity
		print("%s updated in %s's inventory! q: %s" % [item.resource_name, self.name, items[item_index].quantity])
	else:
		var content = ContentItem.new()
		content.item = item
		content.quantity = quantity
		items.append(content)
		print("%s added to %s's inventory! q: %s" % [item.resource_name, self.name, quantity])

##Removes an item from the inventory, if the item already exists in inventory.
func remove_item(item_name: String, quantity: int):
	var item_index = is_item_in_inventory(item_name)
	if item_index >= 0:
		items[item_index].quantity -= quantity
		if items[item_index].quantity > 0:
			print("%s updated in %s's inventory! q: %s" % [item_name, self.name, items[item_index].quantity])
		else:
			items.remove_at(item_index)
			print("%s removed from %s's inventory! q: 0" % [item_name, self.name])

func _update_item_list():
	for content: ContentItem in items:
		var item = content.item
		var item_name = "%s x%s" % [tr(item.resource_name), content.quantity]
		item_list.add_item(item_name, item.icon)

func _on_item_list_item_activated(index: int) -> void:
	var item = items[index].item
	if item is DataWeapon:
		equip_weapon.emit(item)
