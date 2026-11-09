class_name CheckItems
extends Check

@export var items: Array[ContentItem] ## Verify whether the required items are present in the entity's inventory.
@export var remove_items := true ## Remove the items from the inventory after a successful validation.

func check(on = null) -> bool:
	var inventory: Inventory = Globals.get_node_inventory(on)
	if !inventory or items.size() <= 0:
		return true
	for content: ContentItem in items:
		if inventory.is_item_in_inventory(content.item.resource_name, content.quantity) < 0:
			return false
		elif remove_items:
			inventory.remove_item(content.item.resource_name, content.quantity)
	return true
