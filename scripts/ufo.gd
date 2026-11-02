class_name Ufos
extends Node3D
## Latający talerz: pojawia się co jakiś czas, krąży wokół gracza i strzela.
## Duży — niecelny, wolny; mały (od fali 3) — celny, szybki, wart więcej.
## Na raz najwyżej jeden UFO. Węzeł w układzie świata (jak skały).

signal destroyed(points: int, torus_pos: Vector3)
signal fired(torus_pos: Vector3)
signal ship_hit

const SPAWN_DELAY := Vector2(18.0, 30.0)
const SPAWN_DIST := 160.0
const LIFETIME := 30.0
const ORBIT := Vector2(45.0, 150.0)       # trzyma się w tym pierścieniu wokół gracza
const SHOT_SPEED := 70.0
const SHOT_LIFE := 3.0
const SHOT_RANGE := 130.0

const KINDS := {
	"big":   {"radius": 4.5, "speed": 15.0, "spread": 9.0, "cooldown": 1.7, "points": 200, "pitch": 1.0},
	"small": {"radius": 2.6, "speed": 24.0, "spread": 2.5, "cooldown": 1.1, "points": 1000, "pitch": 1.6},
}


class Shot:
	var pos: Vector3
	var vel: Vector3
	var life: float
	var node: MeshInstance3D


var active := false
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var kind: Dictionary = {}
var shots: Array[Shot] = []

var _timer := 0.0
var _age := 0.0
var _turn_t := 0.0
var _shot_cd := 0.0
var _node: Node3D
var _lights: Node3D
var _hum: AudioStreamPlayer3D
var _zap: AudioStreamPlayer3D
var _shot_mesh: SphereMesh
var _shot_mat: StandardMaterial3D


func _ready() -> void:
	_build_saucer()
	_shot_mesh = SphereMesh.new()
	_shot_mesh.radius = 0.55
	_shot_mesh.height = 1.1
	_shot_mesh.radial_segments = 8
	_shot_mesh.rings = 4
	_shot_mat = StandardMaterial3D.new()
	_shot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shot_mat.albedo_color = Color(1.0, 0.2, 0.75)
	reset_timer()


func reset_timer() -> void:
	_timer = randf_range(SPAWN_DELAY.x, SPAWN_DELAY.y)


func clear() -> void:
	_despawn()
	for s in shots:
		s.node.queue_free()
	shots.clear()
	reset_timer()


func set_paused(p: bool) -> void:
	_hum.stream_paused = p
	_zap.stream_paused = p


# ---------------------------------------------------------------- logika

func step(delta: float, view: Vector3, ship_vel: Vector3, wave: int, ship_radius: float) -> void:
	if not active:
		_timer -= delta
		if _timer <= 0.0:
			_spawn(view, wave)
	else:
		_fly(delta, view, ship_vel)
	_step_shots(delta, view, ship_radius)


func _spawn(view: Vector3, wave: int) -> void:
	var small := wave >= 3 and randf() < minf(0.25 + 0.1 * wave, 0.7)
	kind = KINDS["small" if small else "big"]
	var dir := Torus.rand_unit()
	pos = Torus.wrap_pos(view + dir * SPAWN_DIST)
	vel = _orbit_dir(-dir) * kind.speed
	_age = 0.0
	_turn_t = randf_range(1.5, 3.0)
	_shot_cd = 2.0
	active = true
	_node.scale = Vector3.ONE * kind.radius
	_node.visible = true
	_hum.pitch_scale = kind.pitch
	_hum.play()


## Kierunek lotu: głównie bokiem względem gracza, trochę do/od niego.
func _orbit_dir(to_ship: Vector3) -> Vector3:
	var side := to_ship.cross(Torus.rand_unit()).normalized()
	return (side * 0.85 + to_ship.normalized() * randf_range(-0.2, 0.45)).normalized()


func _fly(delta: float, view: Vector3, ship_vel: Vector3) -> void:
	_age += delta
	var rel := Torus.wrap_delta(pos - view)          # UFO względem gracza
	var dist := rel.length()

	_turn_t -= delta
	if _turn_t <= 0.0:
		_turn_t = randf_range(1.5, 3.0)
		var v := _orbit_dir(-rel)
		if dist > ORBIT.y and _age < LIFETIME:
			v = (v - rel.normalized()).normalized()   # za daleko — podleć
		elif dist < ORBIT.x:
			v = (v + rel.normalized()).normalized()   # za blisko — odsuń się
		if _age >= LIFETIME:
			v = rel.normalized()                     # koniec czasu — odlot
		vel = v * kind.speed
	pos = Torus.wrap_pos(pos + vel * delta)
	_node.position = Torus.wrap_delta(pos - view)
	_lights.rotate_y(delta * 2.5)

	if _age >= LIFETIME and dist > SPAWN_DIST + 10.0:
		_despawn()
		reset_timer()
		return

	_shot_cd -= delta
	if _shot_cd <= 0.0 and dist < SHOT_RANGE and _age < LIFETIME:
		_shot_cd = kind.cooldown
		_fire_at(-rel, ship_vel)


func _fire_at(to_ship: Vector3, ship_vel: Vector3) -> void:
	# celowanie z wyprzedzeniem (statek leci prosto), plus rozrzut
	var t := to_ship.length() / SHOT_SPEED
	var aim := (to_ship + ship_vel * t).normalized()
	var spread := deg_to_rad(kind.spread)
	aim = aim.rotated(aim.cross(Torus.rand_unit()).normalized(), randf_range(0.0, spread))
	var s := Shot.new()
	s.pos = pos
	s.vel = aim * SHOT_SPEED
	s.life = SHOT_LIFE
	s.node = MeshInstance3D.new()
	s.node.mesh = _shot_mesh
	s.node.material_override = _shot_mat
	add_child(s.node)
	shots.append(s)
	_zap.play()
	fired.emit(pos)


func _step_shots(delta: float, view: Vector3, ship_radius: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var s := shots[i]
		s.pos = Torus.wrap_pos(s.pos + s.vel * delta)
		s.life -= delta
		# odcinek–kula: trafienie statku
		var seg := s.vel * delta
		var c := Torus.wrap_delta(view - s.pos)
		var tt := clampf((c + seg).dot(seg) / seg.length_squared(), 0.0, 1.0)
		var hit := (c - (-seg + seg * tt)).length() < ship_radius + 0.6
		if hit or s.life <= 0.0:
			s.node.queue_free()
			shots.remove_at(i)
			if hit:
				ship_hit.emit()
		else:
			s.node.position = Torus.wrap_delta(s.pos - view)


## Czy odcinek (end - seg, end] trafia UFO.
func segment_hit(end: Vector3, seg: Vector3) -> bool:
	if not active:
		return false
	var c := Torus.wrap_delta(pos - end)
	var len2 := seg.length_squared()
	var t := clampf((c + seg).dot(seg) / len2, 0.0, 1.0) if len2 > 0.0 else 1.0
	return (c - (-seg + seg * t)).length() < kind.radius * 0.9 + 0.3


func sphere_hit(p: Vector3, radius: float) -> bool:
	return active and Torus.wrap_delta(pos - p).length() < kind.radius * 0.8 + radius


func distance_to(p: Vector3) -> float:
	return Torus.wrap_delta(pos - p).length() if active else INF


func explode() -> void:
	if not active:
		return
	var p := pos
	var pts: int = kind.points
	_despawn()
	reset_timer()
	destroyed.emit(pts, p)


func _despawn() -> void:
	active = false
	_node.visible = false
	_hum.stop()


# ---------------------------------------------------------------- wygląd

func _build_saucer() -> void:
	# Klasyczny latający spodek (promień 1, skalowany rozmiarem UFO):
	# szeroki spłaszczony dysk z obręczą, nadbudówka z wieńcem okrągłych
	# iluminatorów, szklana kopuła, pod spodem wirujące światła.
	_node = Node3D.new()
	_node.visible = false
	add_child(_node)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.78, 0.8, 0.86)
	metal.metallic = 0.9
	metal.roughness = 0.22
	var dark_metal := StandardMaterial3D.new()
	dark_metal.albedo_color = Color(0.35, 0.36, 0.4)
	dark_metal.metallic = 0.9
	dark_metal.roughness = 0.35

	# dolny dysk
	_part(_sphere(1.0, 0.34, 32, 10), metal, Vector3(0, -0.04, 0))
	# obręcz na krawędzi
	var rim := TorusMesh.new()
	rim.inner_radius = 0.95
	rim.outer_radius = 1.04
	rim.rings = 48
	rim.ring_segments = 8
	_part(rim, dark_metal, Vector3(0, -0.04, 0))
	# nadbudówka
	const UP_R := 0.6
	const UP_H := 0.26                       # półoś pionowa
	const UP_Y := 0.07
	_part(_sphere(UP_R, UP_H * 2.0, 32, 12), metal, Vector3(0, UP_Y, 0))
	# szklana kopuła
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.35, 0.95, 0.95, 0.75)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.3
	glass.roughness = 0.05
	glass.emission_enabled = true
	glass.emission = Color(0.1, 0.45, 0.45)
	var dome := _sphere(0.3, 0.3, 20, 8)
	dome.is_hemisphere = true
	_part(dome, glass, Vector3(0, UP_Y + UP_H - 0.04, 0))

	# okrągłe iluminatory na zboczu nadbudówki, prostopadle do powierzchni
	var window_mat := StandardMaterial3D.new()
	window_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	window_mat.albedo_color = Color(1.0, 0.86, 0.5)
	var win := CylinderMesh.new()
	win.top_radius = 0.075
	win.bottom_radius = 0.075
	win.height = 0.02
	win.radial_segments = 16
	var frame := TorusMesh.new()
	frame.inner_radius = 0.072
	frame.outer_radius = 0.095
	frame.rings = 16
	frame.ring_segments = 6
	const N_WIN := 12
	const WIN_Y := 0.1                       # wysokość nad środkiem nadbudówki
	var ring_r := UP_R * sqrt(1.0 - (WIN_Y / UP_H) * (WIN_Y / UP_H))
	for i in N_WIN:
		var ang := TAU * i / N_WIN
		var p := Vector3(cos(ang) * ring_r, UP_Y + WIN_Y, sin(ang) * ring_r)
		# normalna elipsoidy: (x/a², y/b², z/a²)
		var n := Vector3(p.x / (UP_R * UP_R), WIN_Y / (UP_H * UP_H), p.z / (UP_R * UP_R)).normalized()
		var wb := _basis_y_to(n)
		var w := _part(win, window_mat, p + n * 0.005)
		w.basis = wb
		var f := _part(frame, dark_metal, p + n * 0.008)
		f.basis = wb

	# wirujący wieniec świateł pod spodem
	_lights = Node3D.new()
	_node.add_child(_lights)
	var lm := _sphere(0.06, 0.12, 8, 4)
	var colors := [Color(1.0, 0.3, 0.8), Color(0.4, 1.0, 0.4)]
	for i in 12:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = colors[i % 2]
		var a := TAU * i / 12.0
		var l := _part(lm, m, Vector3(cos(a) * 0.72, -0.17, sin(a) * 0.72))
		l.reparent(_lights, false)
	# poświata silnika pod spodem
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.5, 0.9, 1.0)
	var eng := CylinderMesh.new()
	eng.top_radius = 0.28
	eng.bottom_radius = 0.22
	eng.height = 0.04
	eng.radial_segments = 24
	_part(eng, glow, Vector3(0, -0.2, 0))

	# dźwięk lecący razem z talerzem — słychać, skąd nadlatuje
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = SfxSynth.ufo_warble()
	_hum.unit_size = 25.0
	_hum.max_distance = 230.0
	_hum.volume_db = -3.0
	_node.add_child(_hum)
	_zap = AudioStreamPlayer3D.new()
	_zap.stream = SfxSynth.ufo_zap()
	_zap.unit_size = 20.0
	_zap.max_distance = 200.0
	_node.add_child(_zap)


func _sphere(r: float, h: float, seg: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = rings
	return m


func _part(mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	_node.add_child(mi)
	return mi


## Baza obracająca oś Y na kierunek `n` (do ustawiania krążków na powierzchni).
static func _basis_y_to(n: Vector3) -> Basis:
	var x := Vector3.UP.cross(n)
	if x.length() < 1e-4:
		return Basis()
	x = x.normalized()
	return Basis(x, n, x.cross(n))
