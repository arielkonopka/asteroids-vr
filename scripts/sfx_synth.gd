# Asteroids VR — Copyright (C) 2026 Ariel Konopka
# Licensed under the GNU GPL version 3 with an additional permission
# (GPLv3 section 7); see LICENSE and LICENSE-EXCEPTION.

class_name SfxSynth
extends RefCounted
## Proceduralna synteza efektów dźwiękowych do AudioStreamWAV (mono, 16 bit).
## Wszystko liczone raz przy starcie — gra nie potrzebuje plików audio.

const RATE := 22050


static func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


static func _lp_coef(cutoff: float, rate: int) -> float:
	return 1.0 - exp(-TAU * cutoff / rate)


static func _normalize(s: PackedFloat32Array, peak: float) -> void:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	if m > 0.0:
		var k := peak / m
		for i in s.size():
			s[i] *= k


## Zapętlenie bez trzasku: ostatnie `xf` próbek przenikają się z początkiem.
static func _loop_crossfade(s: PackedFloat32Array, xf: int) -> PackedFloat32Array:
	var n := s.size() - xf
	var out := s.slice(0, n)
	for i in xf:
		var a := float(i) / xf
		out[i] = s[i] * a + s[n + i] * (1.0 - a)
	return out


static func _to_wav(s: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


# ---------------------------------------------------------------- efekty

## Działko: krótki opadający "pew".
static func laser() -> AudioStreamWAV:
	var rate := 44100
	var dur := 0.16
	var n := int(dur * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := _rng(1)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 1700.0 * pow(260.0 / 1700.0, t / dur)
		ph += TAU * f / rate
		var env := minf(1.0, t / 0.002) * exp(-t * 16.0)
		s[i] = (tanh(2.5 * sin(ph)) + rng.randf_range(-0.08, 0.08)) * env
	_normalize(s, 0.8)
	return _to_wav(s, rate)


## Wybuch skały; level 0 = duża (dłuższy, głębszy), 2 = mała.
static func explosion(level: int) -> AudioStreamWAV:
	var dur: float = [1.8, 1.1, 0.65][level]
	var cutoff0: float = [900.0, 1500.0, 2600.0][level]
	var thump_f: float = [50.0, 75.0, 115.0][level]
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := _rng(10 + level)
	var y1 := 0.0
	var y2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var a := _lp_coef(cutoff0 * exp(-t * 2.5) + 90.0, RATE)
		var x := rng.randf_range(-1.0, 1.0)
		if t < 0.25 and rng.randf() < 0.004:      # trzaski odłamków
			x *= 12.0
		y1 += a * (x - y1)
		y2 += a * (y1 - y2)
		ph += TAU * thump_f * (1.0 - 0.35 * t / dur) / RATE
		var attack := 1.0 - exp(-t / 0.003)
		var noise := y2 * exp(-t * 3.2 / dur)
		var thump := sin(ph) * exp(-t * 7.0)
		s[i] = attack * (noise * 1.6 + thump * 0.7)
	_normalize(s, 0.95)
	return _to_wav(s, RATE)


## Pętla silnika: niski szum + buczenie, zapętlona.
static func engine() -> AudioStreamWAV:
	var n := RATE                     # 1 s
	var xf := RATE / 10
	var s := PackedFloat32Array()
	s.resize(n + xf)
	var rng := _rng(20)
	var brown := 0.0
	var y := 0.0
	var a := _lp_coef(320.0, RATE)
	for i in n + xf:
		var t := float(i) / RATE
		brown = brown * 0.995 + rng.randf_range(-1.0, 1.0) * 0.1
		y += a * (brown - y)
		var hum := sin(TAU * 46.0 * t) * 0.35 + sin(TAU * 92.0 * t) * 0.15
		s[i] = y * 2.5 + hum * (0.8 + 0.2 * sin(TAU * 6.0 * t))
	s = _loop_crossfade(s, xf)
	_normalize(s, 0.8)
	return _to_wav(s, RATE, true)


## Pętla "skały w pobliżu": głębokie dudnienie z wolnym chrzęstem.
static func rumble() -> AudioStreamWAV:
	var n := RATE * 2
	var xf := RATE / 5
	var s := PackedFloat32Array()
	s.resize(n + xf)
	var rng := _rng(30)
	var y1 := 0.0
	var y2 := 0.0
	var g := 0.0
	var a1 := _lp_coef(110.0, RATE)
	var a2 := _lp_coef(700.0, RATE)
	for i in n + xf:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		y1 += a1 * (x - y1)
		y2 += a2 * (x - y2)
		g = 0.5 + 0.5 * sin(TAU * 2.5 * t + sin(TAU * 0.5 * t) * 2.0)
		s[i] = y1 * 6.0 + y2 * 0.6 * g * g + sin(TAU * 38.0 * t) * 0.25
	s = _loop_crossfade(s, xf)
	_normalize(s, 0.8)
	return _to_wav(s, RATE, true)


## Uderzenie w kadłub: metaliczny brzęk (nieharmoniczne alikwoty) + łomot.
static func clang() -> AudioStreamWAV:
	var dur := 1.2
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := _rng(40)
	var partials := [[173.0, 1.0, 3.0], [268.0, 0.7, 4.0], [401.0, 0.6, 5.5],
			[587.0, 0.45, 7.0], [829.0, 0.3, 9.0], [1163.0, 0.2, 12.0]]
	var y := 0.0
	var a := _lp_coef(500.0, RATE)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for p in partials:
			v += sin(TAU * p[0] * t) * p[1] * exp(-t * p[2])
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		v += y * 4.0 * exp(-t * 10.0)
		s[i] = v * (1.0 - exp(-t / 0.001))
	_normalize(s, 0.9)
	return _to_wav(s, RATE)


## Alarm ostatniego życia: dwa krótkie dwutony.
static func alarm() -> AudioStreamWAV:
	var dur := 0.6
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var seg := int(t / 0.15)
		var f := 880.0 if seg % 2 == 0 else 660.0
		var local := fmod(t, 0.15)
		var env := minf(1.0, local / 0.005) * minf(1.0, (0.15 - local) / 0.01)
		s[i] = tanh(3.0 * sin(TAU * f * t)) * env * 0.5
	_normalize(s, 0.6)
	return _to_wav(s, RATE)


## Sekwencja tonów (akord fali / game over).
static func notes(freqs: Array, step: float, decay: float) -> AudioStreamWAV:
	var dur := step * freqs.size() + decay * 2.5
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for k in freqs.size():
		var f: float = freqs[k]
		var start := int(k * step * RATE)
		for i in range(start, n):
			var t := float(i - start) / RATE
			var env := minf(1.0, t / 0.004) * exp(-t / decay)
			s[i] += (sin(TAU * f * t) + 0.3 * sin(TAU * 2.0 * f * t)) * env
	_normalize(s, 0.6)
	return _to_wav(s, RATE)


## Pętla UFO: klasyczne "łiu-łiu" — sinus z modulacją częstotliwości.
static func ufo_warble() -> AudioStreamWAV:
	# 0,5 s = 4 pełne cykle LFO i dokładnie 320 cykli nośnej → faza wraca do zera, pętla bez szwu
	var n := RATE / 2
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 640.0 + 180.0 * sin(TAU * 8.0 * t)
		ph += TAU * f / RATE
		s[i] = (sin(ph) + 0.25 * sin(2.0 * ph)) * 0.6
	_normalize(s, 0.7)
	return _to_wav(s, RATE, true)


## Strzał UFO: niższy, "brzęczący" zap.
static func ufo_zap() -> AudioStreamWAV:
	var dur := 0.3
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 900.0 * pow(120.0 / 900.0, t / dur)
		ph += TAU * f / RATE
		var env := minf(1.0, t / 0.003) * exp(-t * 9.0)
		s[i] = signf(sin(ph)) * 0.5 * env + sin(ph * 0.5) * 0.4 * env
	_normalize(s, 0.75)
	return _to_wav(s, RATE)


## Zebranie power-upa: szybkie arpeggio w górę.
static func pickup() -> AudioStreamWAV:
	return notes([783.99, 987.77, 1174.66, 1567.98], 0.05, 0.18)
