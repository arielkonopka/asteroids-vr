# Asteroids VR — Copyright (C) 2026 Ariel Konopka
# Licensed under the GNU GPL version 3 with an additional permission
# (GPLv3 section 7); see LICENSE and LICENSE-EXCEPTION.

class_name PowerUps
extends Node3D
## Power-upy: kryształy wypadające ze skał (czasem) i z UFO (zawsze).
## Zbiera się je, przelatując przez nie. Węzeł w układzie świata.

signal picked(type: int)

enum { SHIELD, TRIPLE, LIFE, BOMB }

const INFO := {
	SHIELD: {"letter": "S", "color": Color(0.3, 0.6, 1.0), "weight": 30},
	TRIPLE: {"letter": "3", "color": Color(1.0, 0.6, 0.15), "weight": 30},
	LIFE:   {"letter": "+", "color": Color(0.3, 1.0, 0.4), "weight": 15},
	BOMB:   {"letter": "B", "color": Color(1.0, 0.25, 0.2), "weight": 25},
}
const DROP_CHANCE := 0.08        # z każdej rozbitej skały
const LIFE_TIME := 15.0
const BLINK_TIME := 4.0
const PICK_RADIUS := 5.0         # hojnie — w VR trudno trafić w punkt
const SIZE := 1.6


class Item:
	var type: int
	var pos: Vector3
	var vel: Vector3
	var life: float
	var node: Node3D
	var gem: MeshInstance3D


var items: Array[Item] = []
var allow_life := true           # false, gdy gracz ma już maksimum żyć

var _mesh: SphereMesh


func _ready() -> void:
	# ośmiościan: sfera z 4 segmentami i 2 pierścieniami
	_mesh = SphereMesh.new()
	_mesh.radius = SIZE * 0.5
	_mesh.height = SIZE * 1.3
	_mesh.radial_segments = 4
	_mesh.rings = 2


func maybe_drop(pos: Vector3, vel: Vector3) -> void:
	if randf() < DROP_CHANCE:
		drop(pos, vel)


func drop(pos: Vector3, vel: Vector3) -> void:
	var total := 0
	for t in INFO:
		if t != LIFE or allow_life:
			total += INFO[t].weight
	var roll := randi() % total
	var type := SHIELD
	for t in INFO:
		if t == LIFE and not allow_life:
			continue
		roll -= INFO[t].weight
		if roll < 0:
			type = t
			break
	_spawn(type, pos, vel.limit_length(6.0))


func _spawn(type: int, pos: Vector3, vel: Vector3) -> void:
	var it := Item.new()
	it.type = type
	it.pos = Torus.wrap_pos(pos)
	it.vel = vel
	it.life = LIFE_TIME
	it.node = Node3D.new()
	var c: Color = INFO[type].color
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	it.gem = MeshInstance3D.new()
	it.gem.mesh = _mesh
	it.gem.material_override = m
	it.node.add_child(it.gem)
	var lbl := Label3D.new()
	lbl.text = INFO[type].letter
	lbl.font_size = 96
	lbl.pixel_size = 0.02
	lbl.outline_size = 16
	lbl.modulate = Color.WHITE
	lbl.outline_modulate = c.darkened(0.5)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position.y = SIZE * 1.2
	it.node.add_child(lbl)
	add_child(it.node)
	items.append(it)


func clear() -> void:
	for it in items:
		it.node.queue_free()
	items.clear()


func step(delta: float, view: Vector3) -> void:
	for i in range(items.size() - 1, -1, -1):
		var it := items[i]
		it.life -= delta
		it.pos = Torus.wrap_pos(it.pos + it.vel * delta)
		var rel := Torus.wrap_delta(it.pos - view)
		if rel.length() < PICK_RADIUS:
			picked.emit(it.type)
			it.node.queue_free()
			items.remove_at(i)
			continue
		if it.life <= 0.0:
			it.node.queue_free()
			items.remove_at(i)
			continue
		it.node.position = rel
		it.gem.rotate_y(delta * 2.0)
		# miganie przed zniknięciem
		it.node.visible = it.life > BLINK_TIME or int(it.life * 6.0) % 2 == 0
