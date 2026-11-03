class_name CatCustomer
extends Node2D
## Кот-посетитель: заходит, ждёт, уходит. Заказ и награды живут в main.gd.

signal arrived
signal left

const SPRITE_DIR := "res://assets/cats/"
const FRAME := Rect2(0, 16, 16, 16)  # нижний ряд листа 64x32, первый кадр (кот анфас)
const PIXEL_SCALE := 4.0

var def: Dictionary = {}
var _sprite: Sprite2D
var _idle: Tween


func setup(cat_def: Dictionary) -> void:
	def = cat_def
	var atlas := AtlasTexture.new()
	atlas.atlas = load(SPRITE_DIR + String(def["sprite"])) as Texture2D
	atlas.region = FRAME
	_sprite = Sprite2D.new()
	_sprite.texture = atlas
	_sprite.scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
	_sprite.modulate = Color(String(def.get("tint", "#ffffff")))
	add_child(_sprite)


func enter(target_x: float) -> void:
	var t := create_tween()
	t.tween_property(self, "position:x", target_x, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_callback(_on_arrived)


func leave(happy: bool) -> void:
	if _idle:
		_idle.kill()
	_sprite.position.y = 0.0
	if not happy:
		_sprite.modulate = _sprite.modulate.darkened(0.35)
	var t := create_tween()
	if happy:
		t.tween_property(_sprite, "position:y", -10.0, 0.12)
		t.tween_property(_sprite, "position:y", 0.0, 0.12)
	t.tween_property(self, "position:x", -80.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void: left.emit())


func _on_arrived() -> void:
	_idle = create_tween().set_loops()
	_idle.tween_property(_sprite, "position:y", -2.0, 0.6)
	_idle.tween_property(_sprite, "position:y", 0.0, 0.6)
	arrived.emit()
