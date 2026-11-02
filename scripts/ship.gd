class_name Ship
extends Node3D
## Statek gracza: rig XR, kokpit z zegarami, sterowanie i lot.
##
## Węzeł stoi w (0,0,0) sceny i tylko się obraca (basis). Ruch postępowy
## dzieje się w logicznej pozycji `torus_pos`, względem której rysowany jest świat.

signal menu_pressed

const MAX_PITCH := 1.0           # rad/s
const MAX_YAW := 1.0
const MAX_ROLL := 1.4
const ROT_SMOOTH := 4.0          # im mniej, tym "miękciej" (komfort)
const INVERT_PITCH := true       # lotniczo: drążek od siebie = nos w dół
const THRUST := 25.0             # m/s^2
const BRAKE := 30.0
const MAX_SPEED := 80.0
const RADIUS := 2.0
const DEADZONE := 0.15

const FIRE_COOLDOWN := 0.14
const GUNS := [Vector3(-0.9, -0.5, -1.2), Vector3(0.9, -0.5, -1.2)]
const CONVERGE := Vector3(0.0, -0.5, -40.0)  # punkt zbieżności działek = celownik
const TRIPLE_SPREAD := 4.0       # stopnie, power-up "potrójny strzał"

var xr_active := false
var torus_pos := Vector3(Torus.HALF, Torus.HALF, Torus.HALF)
var vel := Vector3.ZERO
var ang_vel := Vector3.ZERO      # lokalnie: x=pitch, y=yaw, z=roll

var origin: XROrigin3D
var camera: XRCamera3D
var left: XRController3D
var right: XRController3D
var dashboard: Dashboard

var _locator: Node3D
var cross: MeshInstance3D       # celownik (chowany na ekranie startowym)
var _shield: MeshInstance3D
var _wave: MeshInstance3D
var _wave_mat: StandardMaterial3D
var _wave_t := -1.0
var _wave_r := 1.0
var _shield_mat: StandardMaterial3D
var _locator_mat: StandardMaterial3D
var _fire_cd := 0.0
var _gun_idx := 0


func setup(p_xr_active: bool) -> void:
	xr_active = p_xr_active
	origin = XROrigin3D.new()
	add_child(origin)
	camera = XRCamera3D.new()
	camera.near = 0.05
	camera.far = 2000.0
	camera.current = true
	origin.add_child(camera)

	left = XRController3D.new()
	left.tracker = &"left_hand"
	origin.add_child(left)
	right = XRController3D.new()
	right.tracker = &"right_hand"
	origin.add_child(right)
	left.button_pressed.connect(func(action: String):
		if action == "menu_button":
			menu_pressed.emit())

	var hand_mat := StandardMaterial3D.new()
	hand_mat.albedo_color = Color(0.3, 0.6, 0.9)
	_box(left, Vector3(0.05, 0.03, 0.12), Vector3.ZERO, Vector3.ZERO, hand_mat)
	_box(right, Vector3(0.05, 0.03, 0.12), Vector3.ZERO, Vector3.ZERO, hand_mat)

	_build_cockpit()


func reset() -> void:
	vel = Vector3.ZERO
	ang_vel = Vector3.ZERO


# ---------------------------------------------------------------- sterowanie

func read_input() -> Dictionary:
	var rs := Vector2.ZERO
	var ls := Vector2.ZERO
	var thrust := 0.0
	var brake := 0.0
	var fire := false
	if xr_active:
		rs = right.get_vector2(&"primary")
		ls = left.get_vector2(&"primary")
		thrust = left.get_float(&"trigger")
		brake = left.get_float(&"grip")
		fire = right.get_float(&"trigger") > 0.5
	else:
		rs.x = float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
		rs.y = float(Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_DOWN))
		ls.x = float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))
		thrust = float(Input.is_key_pressed(KEY_W))
		brake = float(Input.is_key_pressed(KEY_S))
		fire = Input.is_key_pressed(KEY_SPACE)
	return {
		"pitch": _dz(rs.y) * (-1.0 if INVERT_PITCH else 1.0),
		"yaw": -_dz(rs.x),
		"roll": -_dz(ls.x),
		"thrust": thrust,
		"brake": brake,
		"fire": fire,
	}


func _dz(v: float) -> float:
	return 0.0 if absf(v) < DEADZONE else signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)


## Obrót i ruch statku na podstawie wejścia z read_input().
func fly(inp: Dictionary, delta: float) -> void:
	# obrót: wygładzona prędkość kątowa w układzie statku
	var target := Vector3(inp.pitch * MAX_PITCH, inp.yaw * MAX_YAW, inp.roll * MAX_ROLL)
	ang_vel = ang_vel.lerp(target, 1.0 - exp(-ROT_SMOOTH * delta))
	var b := basis
	b = b * Basis(Vector3.RIGHT, ang_vel.x * delta)
	b = b * Basis(Vector3.UP, ang_vel.y * delta)
	b = b * Basis(Vector3.BACK, ang_vel.z * delta)
	basis = b.orthonormalized()

	# ruch: Newton, bez tarcia; hamulec to wsteczne silniki
	vel += -basis.z * THRUST * inp.thrust * delta
	vel = vel.move_toward(Vector3.ZERO, BRAKE * inp.brake * delta)
	vel = vel.limit_length(MAX_SPEED)
	torus_pos = Torus.wrap_pos(torus_pos + vel * delta)

	if inp.thrust > 0.1:
		haptic(left, 0.08 * inp.thrust, 0.03)
	_fire_cd -= delta


## Jeśli działko jest gotowe, zwraca {gun, pos, dirs} strzału (dwa działka na
## zmianę, zbieżne na celowniku; `triple` = wachlarz trzech pocisków);
## inaczej pusty słownik.
func try_fire(triple := false) -> Dictionary:
	if _fire_cd > 0.0:
		return {}
	_fire_cd = FIRE_COOLDOWN
	var gi := _gun_idx
	var gun: Vector3 = GUNS[gi]
	_gun_idx = (_gun_idx + 1) % GUNS.size()
	haptic(right, 0.35 if triple else 0.25, 0.04)
	var dir := basis * (CONVERGE - gun).normalized()
	var dirs := [dir]
	if triple:
		var spread := deg_to_rad(TRIPLE_SPREAD)
		dirs.append(dir.rotated(basis.y, spread))
		dirs.append(dir.rotated(basis.y, -spread))
	return {
		"gun": gi,
		"pos": Torus.wrap_pos(torus_pos + basis * gun),
		"dirs": dirs,
	}


## Fala uderzeniowa bomby: rozszerzająca się kula do promienia `radius`.
func shockwave(radius: float) -> void:
	_wave_r = radius
	_wave_t = 0.0
	_wave.visible = true


func _process(delta: float) -> void:
	if _wave_t < 0.0:
		return
	const DUR := 0.7
	_wave_t += delta
	var k := _wave_t / DUR
	if k >= 1.0:
		_wave_t = -1.0
		_wave.visible = false
		return
	_wave.scale = Vector3.ONE * lerpf(2.0, _wave_r, 1.0 - pow(1.0 - k, 3.0))
	_wave_mat.albedo_color.a = 0.5 * (1.0 - k)


## Bańka tarczy wokół kokpitu; `strength` 0 = brak, 1 = pełna.
func set_shield(strength: float) -> void:
	_shield.visible = strength > 0.0
	if _shield.visible:
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.008)
		_shield_mat.albedo_color.a = 0.035 * pulse * clampf(strength, 0.3, 1.0)


## Strzałka przy celowniku w stronę celu `rel` (wektor w układzie świata,
## np. wrap_delta(rock - torus_pos)). Zero = ukryj. Znika, gdy cel jest
## już w celowniku; czerwona, gdy cel jest za plecami.
func point_locator(rel: Vector3) -> void:
	if rel == Vector3.ZERO:
		_locator.visible = false
		return
	var local := basis.inverse() * rel
	var ahead := local.normalized().dot(Vector3.FORWARD)
	if ahead > cos(deg_to_rad(4.0)):
		_locator.visible = false
		return
	var v := Vector2(local.x, local.y)
	if v.length() < 1e-3:
		v = Vector2.UP           # dokładnie za plecami — wskaż w górę
	_locator.rotation.z = atan2(v.y, v.x) - PI * 0.5
	_locator_mat.albedo_color = Color(1.0, 0.25, 0.15) if ahead < 0.0 else Color(1.0, 0.85, 0.2)
	_locator.visible = true


func haptic(hand: XRController3D, amplitude: float, duration: float) -> void:
	if xr_active:
		hand.trigger_haptic_pulse(&"haptic", 0.0, amplitude, duration, 0.0)


# ---------------------------------------------------------------- kokpit

func _box(parent: Node3D, size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_cockpit() -> void:
	# Stała rama w polu widzenia = kotwica dla błędnika. To najważniejszy
	# element komfortu przy obrotach statku.
	var cp := Node3D.new()
	cp.name = "Cockpit"
	add_child(cp)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.18, 0.19, 0.22)
	metal.metallic = 0.6
	metal.roughness = 0.5
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.9, 0.45, 0.1)
	trim.emission_enabled = true
	trim.emission = Color(0.9, 0.45, 0.1)
	trim.emission_energy_multiplier = 0.6

	# deska rozdzielcza
	_box(cp, Vector3(1.5, 0.06, 0.55), Vector3(0, -0.45, -0.6), Vector3(-15, 0, 0), metal)
	_box(cp, Vector3(1.5, 0.015, 0.02), Vector3(0, -0.40, -0.86), Vector3(-15, 0, 0), trim)
	# słupki owiewki
	_box(cp, Vector3(0.06, 1.3, 0.06), Vector3(-0.8, 0.05, -0.75), Vector3(-12, 0, 18), metal)
	_box(cp, Vector3(0.06, 1.3, 0.06), Vector3(0.8, 0.05, -0.75), Vector3(-12, 0, -18), metal)
	# belka górna i grzbiet
	_box(cp, Vector3(1.3, 0.06, 0.06), Vector3(0, 0.62, -0.88), Vector3.ZERO, metal)
	_box(cp, Vector3(0.06, 0.06, 1.6), Vector3(0, 0.66, -0.1), Vector3.ZERO, metal)
	# boczne progi / podłokietniki
	_box(cp, Vector3(0.12, 0.08, 1.4), Vector3(-0.6, -0.38, -0.1), Vector3.ZERO, metal)
	_box(cp, Vector3(0.12, 0.08, 1.4), Vector3(0.6, -0.38, -0.1), Vector3.ZERO, metal)
	_box(cp, Vector3(0.02, 0.012, 1.4), Vector3(-0.6, -0.335, -0.1), Vector3.ZERO, trim)
	_box(cp, Vector3(0.02, 0.012, 1.4), Vector3(0.6, -0.335, -0.1), Vector3.ZERO, trim)
	# oparcie fotela
	_box(cp, Vector3(0.7, 1.0, 0.1), Vector3(0, -0.1, 0.45), Vector3(10, 0, 0), metal)

	# celownik — w układzie statku, w punkcie zbieżności działek
	var ring := TorusMesh.new()
	ring.inner_radius = 0.9
	ring.outer_radius = 1.0
	cross = MeshInstance3D.new()
	cross.mesh = ring
	cross.position = CONVERGE
	cross.rotation_degrees = Vector3(90, 0, 0)
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(0.3, 1.0, 0.4)
	cm.disable_fog = true
	cm.no_depth_test = true
	cross.material_override = cm
	cp.add_child(cross)

	# wskaźnik najbliższej skały: strzałka na obwodzie celownika
	_locator = Node3D.new()
	_locator.position = CONVERGE
	_locator.visible = false
	cp.add_child(_locator)
	var pm := PrismMesh.new()
	pm.size = Vector3(1.6, 1.8, 0.05)
	var arrow := MeshInstance3D.new()
	arrow.mesh = pm
	arrow.position.y = 2.3
	_locator_mat = StandardMaterial3D.new()
	_locator_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_locator_mat.disable_fog = true
	_locator_mat.no_depth_test = true
	arrow.material_override = _locator_mat
	_locator.add_child(arrow)

	# tarcza: półprzezroczysta bańka widziana od środka
	var sm := SphereMesh.new()
	sm.radius = 2.2
	sm.height = 4.4
	sm.radial_segments = 32
	sm.rings = 16
	_shield_mat = StandardMaterial3D.new()
	_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shield_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_shield_mat.disable_fog = true
	_shield_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_shield_mat.albedo_color = Color(0.3, 0.6, 1.0, 0.1)
	_shield = MeshInstance3D.new()
	_shield.mesh = sm
	_shield.material_override = _shield_mat
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield.visible = false
	cp.add_child(_shield)

	# fala uderzeniowa bomby (kula jednostkowa, skalowana)
	var wm := SphereMesh.new()
	wm.radius = 1.0
	wm.height = 2.0
	wm.radial_segments = 32
	wm.rings = 16
	_wave_mat = StandardMaterial3D.new()
	_wave_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wave_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_wave_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wave_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_wave_mat.albedo_color = Color(1.0, 0.45, 0.2, 0.5)
	_wave = MeshInstance3D.new()
	_wave.mesh = wm
	_wave.material_override = _wave_mat
	_wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wave.visible = false
	add_child(_wave)

	dashboard = Dashboard.new()
	dashboard.name = "Dashboard"
	cp.add_child(dashboard)
