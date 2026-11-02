# Asteroids VR — Copyright (C) 2026 Ariel Konopka
# Licensed under the GNU GPL version 3 or later, with an additional permission
# (GPLv3 section 7); see LICENSE and LICENSE-EXCEPTION.

class_name Dashboard
extends Node3D
## Zestaw zegarów w kokpicie: życia | prędkość + wynik | skały fali + numer fali.
## Plus linijka komunikatu (PAUZA / GAME OVER), widoczna tylko w razie potrzeby,
## i linijka statusu aktywnych power-upów.

const EYE := Vector3.ZERO        # oczy pilota w układzie kokpitu (LOCAL reference space)

var speed: Gauge
var lives: Gauge
var rocks: Gauge
var message: Label3D
var status: Label3D


func setup(max_speed: float, max_lives: int) -> void:
	speed = Gauge.new()
	speed.radius = 0.075
	speed.max_value = max_speed
	speed.major_step = 10.0
	speed.minor_per_major = 1
	speed.label_every = 2
	speed.title = "m/s"
	speed.red_from = max_speed * 0.875
	speed.red_to = max_speed
	speed.readout_digits = 6
	speed.readout_caption = "SCORE"
	speed.smoothing = 8.0
	_mount(speed, Vector3(0.0, -0.305, -0.6))

	lives = Gauge.new()
	lives.radius = 0.052
	lives.max_value = max_lives
	lives.major_step = 1.0
	lives.minor_per_major = 1
	lives.title = "LIVES"
	lives.red_from = 0.0
	lives.red_to = 1.0
	lives.has_lamp = true
	lives.smoothing = 3.0
	_mount(lives, Vector3(-0.19, -0.325, -0.58))

	rocks = Gauge.new()
	rocks.radius = 0.052
	rocks.max_value = 1.0
	rocks.major_step = 0.25
	rocks.minor_per_major = 1
	rocks.label_scale = 100.0
	rocks.title = "ROCKS %"
	rocks.readout_digits = 2
	rocks.readout_caption = "WAVE"
	rocks.smoothing = 3.0
	_mount(rocks, Vector3(0.19, -0.325, -0.58))

	# panel pod zegarami
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.06, 0.065, 0.075)
	panel_mat.roughness = 0.8
	var bm := BoxMesh.new()
	bm.size = Vector3(0.56, 0.16, 0.02)
	var panel := MeshInstance3D.new()
	panel.mesh = bm
	panel.material_override = panel_mat
	add_child(panel)
	var ppos := Vector3(0.0, -0.315, -0.625)
	panel.transform = Transform3D(Basis.looking_at(EYE - ppos, Vector3.UP, true), ppos)

	message = Label3D.new()
	message.font_size = 48
	message.pixel_size = 0.0011
	message.outline_size = 8
	message.modulate = Color(0.6, 0.8, 1.0)
	var mpos := Vector3(0.0, -0.165, -0.6)
	message.transform = Transform3D(Basis.looking_at(EYE - mpos, Vector3.UP, true), mpos)
	message.visible = false
	add_child(message)

	# aktywne power-upy z pozostałym czasem — nad panelem
	status = Label3D.new()
	status.font_size = 40
	status.pixel_size = 0.0006
	status.outline_size = 0
	status.modulate = Color(0.55, 0.85, 1.0)
	var spos := Vector3(0.0, -0.207, -0.61)
	status.transform = Transform3D(Basis.looking_at(EYE - spos, Vector3.UP, true), spos)
	add_child(status)


func _mount(g: Gauge, pos: Vector3) -> void:
	# Tarcza prostopadle do linii wzroku — czytelna bez przechylania głowy.
	g.transform = Transform3D(Basis.looking_at(EYE - pos, Vector3.UP, true), pos)
	add_child(g)


func show_message(text: String) -> void:
	message.text = text
	message.visible = text != ""


func show_status(text: String) -> void:
	status.text = text
