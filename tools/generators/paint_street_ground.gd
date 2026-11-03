extends SceneTree
## Создаёт TileSet земли (assets/street/tiles/street_tileset.tres) и добавляет в scenes/street.tscn слой Ground (TileMapLayer),
## нарисованный по схеме улицы. Запуск после build_street_scene.py:
##   godot --headless --path . --script res://tools/generators/paint_street_ground.gd
## ВНИМАНИЕ: пересоздаёт слой Ground (ручная покраска земли в сцене будет потеряна).

const TILES := "res://assets/street/tiles/street_tiles.png"
const SET_PATH := "res://assets/street/tiles/street_tileset.tres"
const SCENE := "res://scenes/street.tscn"
const COLS := 82
const ROWS := 30

# координаты тайлов в атласе (см. assets/street/tiles/README.md)
const SIDEWALK := Vector2i(0, 0)
const SIDEWALK_CRACK := Vector2i(1, 0)
const SIDEWALK_WALL := Vector2i(2, 0)
const CURB := Vector2i(3, 0)
const CONCRETE := Vector2i(4, 0)
const CONCRETE_CRACK := Vector2i(5, 0)
const SIDEWALK_B := Vector2i(7, 0)
const ASPHALT := Vector2i(0, 1)
const ASPHALT_B := Vector2i(1, 1)
const ROAD_EDGE := Vector2i(2, 1)
const DASH := Vector2i(3, 1)
const ZEBRA := Vector2i(4, 1)
const GRASS := Vector2i(0, 2)
const GRASS_L := Vector2i(1, 2)
const GRASS_D := Vector2i(2, 2)
const GRASS_FLOWERS := Vector2i(3, 2)

const CROSSWALK_COLS := [34, 35, 36]   # проход напротив прохода между домами


func _init() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = load(TILES)
	src.texture_region_size = Vector2i(16, 16)
	for c in [SIDEWALK, SIDEWALK_CRACK, SIDEWALK_WALL, CURB, CONCRETE, CONCRETE_CRACK, Vector2i(6, 0), SIDEWALK_B, ASPHALT, ASPHALT_B, ROAD_EDGE, DASH, ZEBRA, GRASS, GRASS_L, GRASS_D, GRASS_FLOWERS]:
		src.create_tile(c)
	ts.add_source(src, 0)
	print("save tileset: ", ResourceSaver.save(ts, SET_PATH))

	var root := (load(SCENE) as PackedScene).instantiate()
	var old := root.get_node_or_null("Ground")
	if old != null:
		root.remove_child(old)
		old.free()
	var g := TileMapLayer.new()
	g.name = "Ground"
	g.tile_set = load(SET_PATH)
	g.scale = Vector2(2, 2)   # клетка карты = 16 px арта = 32 px мира
	root.add_child(g)
	root.move_child(g, 0)
	g.owner = root
	for y in ROWS:
		for x in COLS:
			var t := _tile_for(x, y)
			if t.x >= 0:
				g.set_cell(Vector2i(x, y), 0, t)
	var packed := PackedScene.new()
	print("pack: ", packed.pack(root), " save scene: ", ResourceSaver.save(packed, SCENE))
	quit()


func _h(x: int, y: int) -> int:
	return absi(hash(Vector2i(x * 7919, y * 104729)))


func _tile_for(x: int, y: int) -> Vector2i:
	var h := _h(x, y) % 100
	if y < 3:
		return Vector2i(-1, -1)                           # над задним двором — небо
	if y < 9:                                             # задний двор: трава
		if y < 5 and h < 45:
			return GRASS_D
		return GRASS_FLOWERS if h < 8 else (GRASS_L if h < 28 else GRASS)
	if y == 9:
		return CONCRETE_CRACK if h < 12 else CONCRETE      # дорожка вдоль задних стен
	if y < 22:
		return CONCRETE_CRACK if h < 8 else CONCRETE        # проходы между домами (под домами не видно)
	if y == 22:
		return SIDEWALK_WALL                                # тень под фасадами
	if y == 23:
		return SIDEWALK_CRACK if h < 10 else (SIDEWALK_B if h < 40 else SIDEWALK)
	if y == 24:
		return CURB
	if x in CROSSWALK_COLS:
		return ZEBRA                                        # зебра: под ней нет другой разметки
	if y == 25:
		return ROAD_EDGE
	if y == 27:
		return DASH if x % 2 == 0 else ASPHALT             # прерывистая разделительная
	return ASPHALT_B if h < 25 else ASPHALT
