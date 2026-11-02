# Asteroids VR — Copyright (C) 2026 Ariel Konopka
# Licensed under the GNU GPL version 3 with an additional permission
# (GPLv3 section 7); see LICENSE and LICENSE-EXCEPTION.

class_name Torus
extends RefCounted
## Topologia świata: sześcian o boku L z periodycznymi brzegami (3-torus).
##
## Logiczne pozycje leżą w [0, L)^3. Statek fizycznie stoi w (0,0,0) sceny,
## a każdy obiekt jest rysowany w "minimalnym obrazie" względem statku:
## wrap_delta(obj_pos - ship_pos) ∈ [-L/2, L/2)^3.
## Mgła kończy się przed L/2, więc przeskok obrazu jest niewidoczny.

const L := 400.0
const HALF := L * 0.5
const FOG_BEGIN := 40.0
# Wykładnik krzywej mgły (smoothstep^curve): >1 = skały długo wyraźne,
# gasną dopiero tuż przed FOG_END.
const FOG_CURVE := 2.6
const FOG_END := 185.0           # < HALF, żeby nie było widać zawijania


static func wrap_pos(p: Vector3) -> Vector3:
	return Vector3(fposmod(p.x, L), fposmod(p.y, L), fposmod(p.z, L))


static func wrap_delta(d: Vector3) -> Vector3:
	return Vector3(fposmod(d.x + HALF, L) - HALF,
			fposmod(d.y + HALF, L) - HALF,
			fposmod(d.z + HALF, L) - HALF)


static func rand_pos() -> Vector3:
	return Vector3(randf() * L, randf() * L, randf() * L)


static func rand_unit() -> Vector3:
	# równomiernie na sferze
	var z := randf_range(-1.0, 1.0)
	var t := randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(t), r * sin(t), z)
