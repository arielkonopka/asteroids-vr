# Asteroids VR — Copyright (C) 2026 Ariel Konopka
# Licensed under the GNU GPL version 3 or later, with an additional permission
# (GPLv3 section 7); see LICENSE and LICENSE-EXCEPTION.

class_name Bullets
extends Node3D
## Pociski gracza: lot, czas życia i trafienia w skały oraz UFO.

const SPEED := 220.0
# Zasięg względem statku = SPEED * LIFE = 176 m < FOG_END < HALF,
# więc pocisk nigdy nie przeskakuje na drugą stronę torusa w widoku.
const LIFE := 0.8


class Bullet:
	var pos: Vector3
	var vel: Vector3
	var life: float
	var node: MeshInstance3D


var bullets: Array[Bullet] = []

var _mesh: SphereMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	_mesh = SphereMesh.new()
	_mesh.radius = 0.3
	_mesh.height = 0.6
	_mesh.radial_segments = 6
	_mesh.rings = 3
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.6, 0.2)   # mgła działa: gasną razem ze skałami


func fire(pos: Vector3, vel: Vector3) -> void:
	var b := Bullet.new()
	b.pos = pos
	b.vel = vel
	b.life = LIFE
	b.node = MeshInstance3D.new()
	b.node.mesh = _mesh
	b.node.material_override = _mat
	add_child(b.node)
	bullets.append(b)


func clear() -> void:
	for b in bullets:
		b.node.queue_free()
	bullets.clear()


## Ruch pocisków i trafienia. Kolizja to test odcinek–kula, bo przy 220 m/s
## pocisk przelatuje ~3 m na klatkę i mógłby "przeskoczyć" małą skałę.
func step(delta: float, view_pos: Vector3, rocks: RockField, ufos: Ufos) -> void:
	for bi in range(bullets.size() - 1, -1, -1):
		var bl := bullets[bi]
		bl.pos = Torus.wrap_pos(bl.pos + bl.vel * delta)
		bl.life -= delta
		var seg := bl.vel * delta
		var hit := false
		if ufos.segment_hit(bl.pos, seg):
			ufos.explode()
			hit = true
		else:
			var ri := rocks.segment_hit(bl.pos, seg)
			if ri >= 0:
				rocks.break_rock(ri, bl.vel)
				hit = true
		if hit or bl.life <= 0.0:
			bl.node.queue_free()
			bullets.remove_at(bi)
		else:
			bl.node.position = Torus.wrap_delta(bl.pos - view_pos)
