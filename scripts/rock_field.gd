class_name RockField
extends Node3D
## Asteroidy: proceduralne siatki, fale, ruch, pękanie i testy kolizji.

signal rock_destroyed(level: int, torus_pos: Vector3)
signal cleared

const SIZES := [12.0, 6.0, 3.0]  # promienie dla poziomów 0,1,2
const START_ROCKS := 8
const SAFE_SPAWN_DIST := 80.0    # nowa fala nie pojawia się bliżej statku
const SPLIT_KICK := Vector2(6.0, 12.0)


class Rock:
	var pos: Vector3
	var vel: Vector3
	var level: int
	var radius: float
	var node: MeshInstance3D
	var spin_axis: Vector3
	var spin_rate: float


var rocks: Array[Rock] = []

var _meshes: Array[Mesh] = []
var _mat: StandardMaterial3D


func _ready() -> void:
	for k in 5:
		_meshes.append(_make_rock_mesh(randi()))
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.55, 0.5, 0.46)
	_mat.roughness = 0.95
	# lekka poświata: cienista strona nie zlewa się z czarnym tłem
	_mat.emission_enabled = true
	_mat.emission = Color(0.16, 0.15, 0.17)
	_mat.rim_enabled = true
	_mat.rim = 0.5
	_mat.rim_tint = 0.3


func _make_rock_mesh(seed_val: int) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 8
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 1.1
	for i in verts.size():
		var v := verts[i]
		var dir := v.normalized() if v.length() > 1e-4 else Vector3.UP
		verts[i] = dir * (1.0 + 0.38 * n.get_noise_3dv(dir))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)          # płaskie cieniowanie = low-poly
	for j in idx:
		st.add_vertex(verts[j])
	st.generate_normals()
	return st.commit()


func spawn(pos: Vector3, vel: Vector3, level: int) -> void:
	var r := Rock.new()
	r.pos = Torus.wrap_pos(pos)
	r.vel = vel
	r.level = level
	r.radius = SIZES[level]
	r.spin_axis = Torus.rand_unit()
	r.spin_rate = randf_range(0.2, 0.6) * (level + 1)
	r.node = MeshInstance3D.new()
	r.node.mesh = _meshes.pick_random()
	r.node.material_override = _mat
	r.node.basis = Basis(Torus.rand_unit(), randf() * TAU).scaled(Vector3.ONE * r.radius)
	add_child(r.node)
	rocks.append(r)


## Ile trafień potrzeba, żeby zniszczyć skałę danego poziomu razem z odłamkami
## (duża: 1 + 2 + 4 = 7).
static func hits_to_clear(level: int) -> int:
	return (1 << (SIZES.size() - level)) - 1


## Jaka część fali została do zniszczenia, 1 → 0.
func remaining_fraction() -> float:
	if _wave_hits == 0:
		return 0.0
	var left := 0
	for r in rocks:
		left += hits_to_clear(r.level)
	return float(left) / _wave_hits


var _wave_hits := 0


func spawn_wave(wave: int, avoid: Vector3) -> void:
	var n := START_ROCKS + 2 * (wave - 1)
	_wave_hits = n * hits_to_clear(0)
	for i in n:
		var p := avoid
		while Torus.wrap_delta(p - avoid).length() < SAFE_SPAWN_DIST:
			p = Torus.rand_pos()
		spawn(p, Torus.rand_unit() * randf_range(5.0, 12.0) * (1.0 + 0.1 * wave), 0)


func clear() -> void:
	for r in rocks:
		r.node.queue_free()
	rocks.clear()


## Ruch skał i ustawienie ich obrazów względem punktu widzenia.
func step(delta: float, view_pos: Vector3) -> void:
	for r in rocks:
		r.pos = Torus.wrap_pos(r.pos + r.vel * delta)
		r.node.position = Torus.wrap_delta(r.pos - view_pos)
		r.node.rotate(r.spin_axis, r.spin_rate * delta)


## Indeks pierwszej skały przeciętej odcinkiem (end - seg, end], albo -1.
func segment_hit(end: Vector3, seg: Vector3) -> int:
	var a := -seg                                  # początek odcinka względem końca
	var len2 := seg.length_squared()
	for i in rocks.size():
		var rk := rocks[i]
		var c := Torus.wrap_delta(rk.pos - end)    # skała względem końca odcinka
		var t := clampf((c - a).dot(seg) / len2, 0.0, 1.0) if len2 > 0.0 else 1.0
		if (c - (a + seg * t)).length() < rk.radius * 0.9 + 0.3:
			return i
	return -1


## Wektor (w układzie świata) od `view` do najbliższej skały; zero, gdy brak skał.
func nearest(view: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := INF
	for r in rocks:
		var d := Torus.wrap_delta(r.pos - view)
		if d.length_squared() < bd:
			bd = d.length_squared()
			best = d
	return best


## Indeks pierwszej skały nachodzącej na kulę (pos, radius), albo -1.
func sphere_hit(pos: Vector3, radius: float) -> int:
	for i in rocks.size():
		var rk := rocks[i]
		if Torus.wrap_delta(rk.pos - pos).length() < rk.radius * 0.85 + radius:
			return i
	return -1


func break_rock(i: int, hit_dir: Vector3) -> void:
	# Pęknięcie wzdłuż płaszczyzny zawierającej kierunek trafienia:
	# dwa odłamki dostają ±kick prostopadle do hit_dir, więc pęd
	# (przy równych masach odłamków) jest zachowany, plus małe pchnięcie od pocisku.
	var r := rocks[i]
	rocks.remove_at(i)
	r.node.queue_free()
	if r.level < SIZES.size() - 1:
		var d := hit_dir.normalized()
		var n := d.cross(Torus.rand_unit())
		if n.length() < 0.01:
			n = d.cross(Vector3.UP)
		n = n.normalized()
		var kick := randf_range(SPLIT_KICK.x, SPLIT_KICK.y)
		for s in [-1.0, 1.0]:
			spawn(r.pos + n * s * r.radius * 0.5, r.vel + d * 3.0 + n * s * kick, r.level + 1)
	rock_destroyed.emit(r.level, r.pos)
	if rocks.is_empty():
		cleared.emit()


## Zniszczenie skały w całości, bez odłamków (bomba).
func destroy(i: int) -> void:
	var r := rocks[i]
	rocks.remove_at(i)
	r.node.queue_free()
	_wave_hits -= hits_to_clear(r.level) - 1    # odłamki już nie powstaną
	rock_destroyed.emit(r.level, r.pos)
	if rocks.is_empty():
		cleared.emit()
