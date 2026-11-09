extends TileMapLayer
##To be added to the TileMapLayer that uses the Navigation Layer.
##This script removes from the navigation region the tiles with id == obstacle_tile_id found in the TileMapLayer set in obstacle_tilemap.

@export var obstacle_tilemap: TileMapLayer ##The TileMapLayer that has the obstacles.
@export var obstacle_tile_id: int ##The tile id of the obstacles. Tile id can be found in the TileSet tab when setting up the Tile Sources.

func _use_tile_data_runtime_update(coords: Vector2i) -> bool:
	if not obstacle_tilemap:
		return false
	if coords in obstacle_tilemap.get_used_cells_by_id(obstacle_tile_id):
		return true
	return false

func _tile_data_runtime_update(coords: Vector2i, tile_data: TileData) -> void:
	if not obstacle_tilemap:
		return
	if coords in obstacle_tilemap.get_used_cells_by_id(obstacle_tile_id):
		tile_data.set_navigation_polygon(0, null)
