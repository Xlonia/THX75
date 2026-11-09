extends Node2D
## Adds or removes items from an entity inventory.

@export var contents: Array[ContentItem] ## A list of items to be obtained.

signal contents_got

func get_contents(params):
	var entity: CharacterEntity = params.get("entity", null)
	if !entity:
		push_warning("Entity is missing in %s" % [get_path()])
		return
	var inventory: Inventory = Globals.get_node_inventory(entity)
	if !inventory:
		push_warning("No inventory found in %s" % [entity.name])
		return
	if contents.size() == 0 or not entity:
		return
	for content in contents:
		if content.quantity > 0:
			inventory.add_item(content.item, content.quantity)
	contents_got.emit.call_deferred()
