# Asteroids VR — Copyright (C) 2026 Ariel Konopka
# Licensed under the GNU GPL version 3 or later, with an additional permission
# (GPLv3 section 7); see LICENSE and LICENSE-EXCEPTION.

extends Node3D
## Asteroids VR — kokpit w 3-torusie.
##
## Ten skrypt składa grę i prowadzi jej stan: ekran startowy → gra → game over,
## wynik, życia, fale, pauza, power-upy, rekord. Topologia jest w Torus,
## statek w Ship, skały w RockField, pociski w Bullets, UFO w Ufos,
## power-upy w PowerUps, dźwięk w Sound.

enum Mode { TITLE, PLAYING, GAME_OVER }

const POINTS := [20, 50, 100]    # za skałę poziomu 0,1,2
const START_LIVES := 3
const MAX_LIVES := 5
const INVULN_TIME := 3.0
const GAME_OVER_TIME := 4.0
# wskaźnik najbliższej skały: gdy zostało mało skał albo żadnej nie widać we mgle
const LOCATOR_ROCKS := 3
const LOCATOR_DIST := 130.0
# power-upy
const SHIELD_TIME := 10.0
const TRIPLE_TIME := 12.0
const BOMB_RADIUS := 70.0
const SAVE_PATH := "user://asteroids.cfg"

var xr_active := false
var ship: Ship
var rocks: RockField
var bullets: Bullets
var ufos: Ufos
var powerups: PowerUps
var sound: Sound
var title: TitleScreen

var mode := Mode.TITLE
var score := 0
var high_score := 0
var lives := START_LIVES
var wave := 0
var invuln := 0.0
var shield_t := 0.0
var triple_t := 0.0
var game_over_t := 0.0
var paused := false
var xr_focused := true           # false, gdy otwarte menu systemowe / zdjęte gogle
var _need_release := true        # start dopiero po puszczeniu i ponownym wciśnięciu spustu


func _ready() -> void:
	randomize()
	_setup_xr()
	_setup_environment()
	_build_stars()

	ship = Ship.new()
	ship.name = "Ship"
	add_child(ship)
	ship.setup(xr_active)
	ship.dashboard.setup(Ship.MAX_SPEED, MAX_LIVES)
	ship.menu_pressed.connect(func():
		if mode == Mode.PLAYING:
			paused = not paused)

	rocks = RockField.new()
	rocks.name = "Rocks"
	add_child(rocks)
	rocks.cleared.connect(func():
		if mode == Mode.PLAYING:
			_next_wave())

	bullets = Bullets.new()
	bullets.name = "Bullets"
	add_child(bullets)

	ufos = Ufos.new()
	ufos.name = "Ufos"
	add_child(ufos)

	powerups = PowerUps.new()
	powerups.name = "PowerUps"
	add_child(powerups)

	sound = Sound.new()
	sound.name = "Sound"
	add_child(sound)
	sound.setup(ship)

	rocks.rock_destroyed.connect(_on_rock_destroyed)
	ufos.destroyed.connect(_on_ufo_destroyed)
	ufos.ship_hit.connect(func():
		if shield_t <= 0.0 and invuln <= 0.0:
			_hurt())
	powerups.picked.connect(_on_powerup)

	title = TitleScreen.new()
	title.name = "Title"
	ship.add_child(title)          # tablica w układzie kokpitu

	_load_high_score()
	_enter_title(-1)


func _setup_xr() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		xr_active = true
		# Sesja traci fokus przy menu systemowym Meta i po zdjęciu gogli.
		xr.session_focussed.connect(func(): xr_focused = true)
		xr.session_visible.connect(func(): xr_focused = false)
		xr.session_stopping.connect(func(): xr_focused = false)
		print("OpenXR aktywny")
	else:
		print("Brak OpenXR — tryb desktopowy (klawiatura)")


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.38, 0.46)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = env.background_color
	env.fog_density = 1.0
	env.fog_depth_begin = Torus.FOG_BEGIN
	env.fog_depth_end = Torus.FOG_END
	env.fog_depth_curve = Torus.FOG_CURVE
	# Niebo tylko do odbić (tło zostaje czarne): bez niego metal odbija
	# czerń i wygląda jak matowa plama. Statyczne, liczone raz.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.08, 0.14)
	sky_mat.sky_horizon_color = Color(0.42, 0.45, 0.55)
	sky_mat.ground_horizon_color = Color(0.3, 0.3, 0.36)
	sky_mat.ground_bottom_color = Color(0.03, 0.03, 0.05)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	sun.light_energy = 1.3
	add_child(sun)
	_build_sun_disc(sun.basis.z)   # światło leci wzdłuż -Z, więc słońce jest w +Z


func _build_sun_disc(dir: Vector3) -> void:
	# Słońce "w nieskończoności" jak gwiazdy: bez zawijania i paralaksy.
	# Tarcza ~3° + poświata jako addytywny billboard (tańsze niż glow w VR).
	const DIST := 950.0
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.97, 0.88)
	core_mat.disable_fog = true
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 24.0
	core_mesh.height = 48.0
	core_mesh.radial_segments = 24
	core_mesh.rings = 12
	var core := MeshInstance3D.new()
	core.mesh = core_mesh
	core.material_override = core_mat
	core.position = dir * DIST
	add_child(core)

	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.97, 0.85, 1.0), Color(1.0, 0.92, 0.7, 0.6),
			Color(1.0, 0.85, 0.55, 0.16), Color(1.0, 0.8, 0.5, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.albedo_texture = tex
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.disable_fog = true
	halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 260.0
	var halo := MeshInstance3D.new()
	halo.mesh = quad
	halo.material_override = halo_mat
	halo.position = dir * (DIST - 30.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)


func _build_stars() -> void:
	# Gwiazdy są "w nieskończoności": nie biorą udziału w zawijaniu
	# i nie mają paralaksy translacji — tylko obrót statku je przesuwa.
	var star := SphereMesh.new()
	star.radius = 1.4
	star.height = 2.8
	star.radial_segments = 4
	star.rings = 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star
	mm.instance_count = 1500
	for i in mm.instance_count:
		var s := randf_range(0.4, 1.4)
		var b := Basis().scaled(Vector3.ONE * s)
		mm.set_instance_transform(i, Transform3D(b, Torus.rand_unit() * 900.0))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.88, 1.0)
	mat.disable_fog = true
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


# ---------------------------------------------------------------- stan gry

func _enter_title(last_score: int) -> void:
	mode = Mode.TITLE
	paused = false
	_clear_world()
	wave = 0
	rocks.spawn_wave(1, ship.torus_pos)     # skały dryfują w tle
	ship.reset()
	ship.set_shield(0.0)
	ship.point_locator(Vector3.ZERO)
	ship.dashboard.show_message("")
	ship.dashboard.show_status("")
	title.open(high_score, last_score, xr_active)
	ship.cross.visible = false
	_need_release = true


func _start_game() -> void:
	title.visible = false
	ship.cross.visible = true
	_clear_world()
	ship.reset()
	score = 0
	lives = START_LIVES
	wave = 0
	invuln = INVULN_TIME
	shield_t = 0.0
	triple_t = 0.0
	mode = Mode.PLAYING
	_next_wave()


func _clear_world() -> void:
	rocks.clear()
	bullets.clear()
	ufos.clear()
	powerups.clear()


func _next_wave() -> void:
	wave += 1
	rocks.spawn_wave(wave, ship.torus_pos)
	sound.wave_start()


func _game_over() -> void:
	mode = Mode.GAME_OVER
	game_over_t = GAME_OVER_TIME
	ufos.clear()
	shield_t = 0.0
	triple_t = 0.0
	ship.set_shield(0.0)
	sound.game_over()
	if score > high_score:
		high_score = score
		_save_high_score()


func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = cfg.get_value("score", "high", 0)


func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "high", high_score)
	cfg.save(SAVE_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_P:
				if mode == Mode.PLAYING:
					paused = not paused
			KEY_ENTER:
				if mode == Mode.TITLE:
					_start_game()
			KEY_ESCAPE:
				get_tree().quit()


# ---------------------------------------------------------------- zdarzenia

func _on_rock_destroyed(level: int, pos: Vector3) -> void:
	sound.explosion(level, pos)
	if mode == Mode.PLAYING:
		score += POINTS[level]
		powerups.maybe_drop(pos, Vector3.ZERO)


func _on_ufo_destroyed(points: int, pos: Vector3) -> void:
	sound.explosion(0, pos)
	score += points
	powerups.drop(pos, Vector3.ZERO)     # UFO zawsze zostawia power-up


func _on_powerup(type: int) -> void:
	sound.pickup()
	ship.haptic(ship.left, 0.5, 0.15)
	ship.haptic(ship.right, 0.5, 0.15)
	match type:
		PowerUps.SHIELD:
			shield_t = SHIELD_TIME
		PowerUps.TRIPLE:
			triple_t = TRIPLE_TIME
		PowerUps.LIFE:
			lives = mini(lives + 1, MAX_LIVES)
		PowerUps.BOMB:
			_bomb()


func _bomb() -> void:
	ship.shockwave(BOMB_RADIUS)
	sound.explosion(0, ship.torus_pos)
	if ufos.distance_to(ship.torus_pos) < BOMB_RADIUS:
		ufos.explode()
	# od końca: destroy() usuwa z tablicy; ostatnie usunięcie może
	# uruchomić nową falę, ale wtedy pętla już się kończy
	for i in range(rocks.rocks.size() - 1, -1, -1):
		if i < rocks.rocks.size() and \
				Torus.wrap_delta(rocks.rocks[i].pos - ship.torus_pos).length() < BOMB_RADIUS:
			rocks.destroy(i)


func _hurt() -> void:
	lives -= 1
	invuln = INVULN_TIME
	ship.haptic(ship.left, 1.0, 0.4)
	ship.haptic(ship.right, 1.0, 0.4)
	sound.hit(lives == 0)
	if lives < 0:
		_game_over()


# ---------------------------------------------------------------- pętla

func _process(delta: float) -> void:
	var dash := ship.dashboard
	var frozen := paused or not xr_focused
	sound.set_paused(frozen)
	ufos.set_paused(frozen)
	if frozen:
		if mode == Mode.PLAYING:
			dash.show_message("PAUSED — %s to resume" % ("left menu button" if xr_active else "P"))
		return

	match mode:
		Mode.TITLE:
			_process_title(delta)
		Mode.GAME_OVER:
			_process_game_over(delta)
		Mode.PLAYING:
			_process_playing(delta)
	_update_hud()


func _process_title(delta: float) -> void:
	var inp := ship.read_input()
	if not inp.fire:
		_need_release = false
	elif not _need_release:
		_start_game()
		return
	rocks.step(delta, ship.torus_pos)
	sound.step(delta, 0.0, rocks.rocks)


func _process_game_over(delta: float) -> void:
	game_over_t -= delta
	ship.dashboard.show_message("GAME OVER")
	rocks.step(delta, ship.torus_pos)
	bullets.step(delta, ship.torus_pos, rocks, ufos)
	sound.step(delta, 0.0, rocks.rocks)
	if game_over_t <= 0.0:
		_enter_title(score)


func _process_playing(delta: float) -> void:
	ship.dashboard.show_message("")
	invuln = maxf(invuln - delta, 0.0)
	shield_t = maxf(shield_t - delta, 0.0)
	triple_t = maxf(triple_t - delta, 0.0)
	powerups.allow_life = lives < MAX_LIVES

	var inp := ship.read_input()
	ship.fly(inp, delta)
	if inp.fire:
		var shot := ship.try_fire(triple_t > 0.0)
		if shot:
			for dir in shot.dirs:
				bullets.fire(shot.pos, ship.vel + dir * Bullets.SPEED)
			sound.shot(shot.gun)

	rocks.step(delta, ship.torus_pos)
	ufos.step(delta, ship.torus_pos, ship.vel, wave, Ship.RADIUS)
	powerups.step(delta, ship.torus_pos)
	var near := rocks.nearest(ship.torus_pos)
	var show_locator := rocks.rocks.size() <= LOCATOR_ROCKS or near.length() > LOCATOR_DIST
	ship.point_locator(near if show_locator else Vector3.ZERO)
	bullets.step(delta, ship.torus_pos, rocks, ufos)
	sound.step(delta, inp.thrust, rocks.rocks)
	if mode == Mode.PLAYING:
		_check_ship_collision()
	ship.set_shield(shield_t / SHIELD_TIME if shield_t > 0.0 else 0.0)


func _check_ship_collision() -> void:
	if ufos.sphere_hit(ship.torus_pos, Ship.RADIUS):
		ufos.explode()
		if shield_t <= 0.0 and invuln <= 0.0:
			_hurt()
			if mode != Mode.PLAYING:
				return

	var ri := rocks.sphere_hit(ship.torus_pos, Ship.RADIUS)
	if ri < 0:
		return
	var d := Torus.wrap_delta(rocks.rocks[ri].pos - ship.torus_pos)
	if shield_t > 0.0:
		# tarcza: taranujemy skałę, statek lekko odbija
		ship.vel = ship.vel.bounce(d.normalized()) * 0.8 if d.length() > 0.0 else ship.vel
		rocks.break_rock(ri, d)
		ship.haptic(ship.left, 0.6, 0.15)
		ship.haptic(ship.right, 0.6, 0.15)
		return
	if invuln > 0.0:
		return
	ship.vel = ship.vel.bounce(d.normalized()) * 0.5 if d.length() > 0.0 else Vector3.ZERO
	rocks.break_rock(ri, d)
	_hurt()


func _update_hud() -> void:
	var dash := ship.dashboard
	dash.speed.set_value(ship.vel.length())
	dash.speed.set_readout(high_score if mode == Mode.TITLE else score)
	dash.lives.set_value(START_LIVES if mode == Mode.TITLE else maxi(lives, 0))
	dash.rocks.set_value(rocks.remaining_fraction())
	dash.rocks.set_readout(wave)
	# kontrolka: ostatnie życie świeci, w czasie nietykalności miga
	var blink := invuln > 0.0 and int(invuln * 6.0) % 2 == 0
	dash.lives.set_lamp(mode == Mode.PLAYING and (lives <= 0 or blink))

	var st: PackedStringArray = []
	if shield_t > 0.0:
		st.append("SHIELD %d s" % ceili(shield_t))
	if triple_t > 0.0:
		st.append("TRIPLE SHOT %d s" % ceili(triple_t))
	dash.show_status("     ".join(st))
