class_name Sound
extends Node3D
## Dźwięk gry. Węzeł stoi w (0,0,0) sceny w układzie świata (jak skały),
## więc źródła 3D ustawiamy w minimalnym obrazie względem statku.
## Słuchaczem jest kamera XR — kierunek dźwięku podąża za głową.

const HUM_VOICES := 4            # ile najbliższych skał "dudni"
const HUM_PITCH := [0.6, 0.85, 1.25]
const HUM_UNIT := [16.0, 9.0, 5.0]
const BOOM_VOICES := 8

var _ship: Ship
var _laser: Array[AudioStreamPlayer3D] = []
var _booms: Array[AudioStreamPlayer3D] = []
var _boom_pos: Array[Vector3] = []
var _boom_next := 0
var _hums: Array[AudioStreamPlayer3D] = []
var _hum_rock: Array = []        # RockField.Rock albo null
var _engine: AudioStreamPlayer
var _ui: AudioStreamPlayer
var _ui2: AudioStreamPlayer
var _ui3: AudioStreamPlayer
var _paused := false

var _s_boom: Array[AudioStreamWAV] = []
var _s_clang: AudioStreamWAV
var _s_alarm: AudioStreamWAV
var _s_wave: AudioStreamWAV
var _s_over: AudioStreamWAV
var _s_pickup: AudioStreamWAV


func setup(ship: Ship) -> void:
	_ship = ship
	var t0 := Time.get_ticks_msec()

	var laser := SfxSynth.laser()
	for gun in Ship.GUNS:
		var p := AudioStreamPlayer3D.new()
		p.stream = laser
		p.position = gun
		p.unit_size = 3.0
		p.volume_db = -8.0
		p.max_polyphony = 3
		ship.add_child(p)        # działka obracają się ze statkiem
		_laser.append(p)

	for lvl in RockField.SIZES.size():
		_s_boom.append(SfxSynth.explosion(lvl))
	for i in BOOM_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 35.0
		p.max_distance = 260.0
		add_child(p)
		_booms.append(p)
		_boom_pos.append(Vector3.ZERO)

	var rumble := SfxSynth.rumble()
	for i in HUM_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.stream = rumble
		p.max_distance = 140.0
		p.volume_db = -4.0
		add_child(p)
		_hums.append(p)
		_hum_rock.append(null)

	_engine = AudioStreamPlayer.new()
	_engine.stream = SfxSynth.engine()
	_engine.volume_db = -30.0
	add_child(_engine)
	_engine.play()

	_ui = AudioStreamPlayer.new()
	add_child(_ui)
	_ui2 = AudioStreamPlayer.new()
	add_child(_ui2)
	_s_clang = SfxSynth.clang()
	_s_alarm = SfxSynth.alarm()
	_s_wave = SfxSynth.notes([392.0, 523.25, 659.25, 783.99], 0.11, 0.35)
	_s_over = SfxSynth.notes([392.0, 329.63, 261.63, 196.0], 0.35, 0.5)
	_s_pickup = SfxSynth.pickup()
	_ui3 = AudioStreamPlayer.new()
	add_child(_ui3)
	print("Synteza dźwięków: %d ms" % (Time.get_ticks_msec() - t0))


# ---------------------------------------------------------------- zdarzenia

func shot(gun: int) -> void:
	_laser[gun].pitch_scale = randf_range(0.94, 1.06)
	_laser[gun].play()


func explosion(level: int, torus_pos: Vector3) -> void:
	var p := _booms[_boom_next]
	_boom_pos[_boom_next] = torus_pos
	_boom_next = (_boom_next + 1) % BOOM_VOICES
	p.stream = _s_boom[level]
	p.pitch_scale = randf_range(0.9, 1.1)
	p.position = Torus.wrap_delta(torus_pos - _ship.torus_pos)
	p.play()


func hit(last_life: bool) -> void:
	_ui.stream = _s_clang
	_ui.play()
	if last_life:
		_ui2.stream = _s_alarm
		_ui2.play()


func wave_start() -> void:
	_ui2.stream = _s_wave
	_ui2.play()


func pickup() -> void:
	_ui3.stream = _s_pickup
	_ui3.play()


func game_over() -> void:
	_ui2.stream = _s_over
	_ui2.play()


func set_paused(p: bool) -> void:
	if p == _paused:
		return
	_paused = p
	for n in find_children("*", "AudioStreamPlayer3D", false, false) + _laser:
		n.stream_paused = p
	for n: AudioStreamPlayer in [_engine, _ui, _ui2, _ui3]:
		n.stream_paused = p


# ---------------------------------------------------------------- co klatkę

func step(delta: float, thrust: float, rocks: Array) -> void:
	var view := _ship.torus_pos

	# wybuchy zostają w miejscu świata, choć statek leci dalej
	for i in BOOM_VOICES:
		if _booms[i].playing:
			_booms[i].position = Torus.wrap_delta(_boom_pos[i] - view)

	# silnik: bieg jałowy + ciąg
	var target_db := lerpf(-30.0, -9.0, thrust)
	_engine.volume_db = lerpf(_engine.volume_db, target_db, 1.0 - exp(-8.0 * delta))
	_engine.pitch_scale = lerpf(_engine.pitch_scale, 0.8 + 0.5 * thrust, 1.0 - exp(-4.0 * delta))

	_update_hums(rocks, view)


func _update_hums(rocks: Array, view: Vector3) -> void:
	# najbliższe HUM_VOICES skał (sortowanie przez wybór — skał jest kilkadziesiąt)
	var near: Array = []
	var dist: Array[float] = []
	for r in rocks:
		var d := Torus.wrap_delta(r.pos - view).length()
		if d > 140.0:
			continue
		var k := near.size()
		while k > 0 and dist[k - 1] > d:
			k -= 1
		if k < HUM_VOICES:
			near.insert(k, r)
			dist.insert(k, d)
			if near.size() > HUM_VOICES:
				near.pop_back()
				dist.pop_back()

	# głos zachowuje swoją skałę, póki jest wśród najbliższych (bez przeskoków)
	for i in HUM_VOICES:
		if _hum_rock[i] != null and not near.has(_hum_rock[i]):
			_hum_rock[i] = null
	for r in near:
		if _hum_rock.has(r):
			continue
		var free := _hum_rock.find(null)
		_hum_rock[free] = r
		var p := _hums[free]
		p.pitch_scale = HUM_PITCH[r.level] * randf_range(0.92, 1.08)
		p.unit_size = HUM_UNIT[r.level]
		p.play(randf() * 1.5)

	for i in HUM_VOICES:
		var p := _hums[i]
		var r = _hum_rock[i]
		if r == null:
			if p.playing:
				p.stop()
		else:
			p.position = Torus.wrap_delta(r.pos - view)
