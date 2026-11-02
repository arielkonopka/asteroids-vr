class_name Gauge
extends Node3D
## Analogowy zegar jak w samochodzie: tarcza, wskazówka, opcjonalne okienko
## z cyframi (jak licznik kilometrów) i kontrolka.
##
## Tarcza jest rysowana raz w 2D (SubViewport) i zamieniana na teksturę
## z mipmapami — w grze kosztuje tyle co jeden quad. Wskazówka to obiekt 3D.
## Zegar leży w płaszczyźnie XY i "patrzy" w +Z.

const SWEEP := 270.0             # zakres wskazówki w stopniach
const TEX := 512                 # rozdzielczość tarczy
const R_PX := 236.0              # promień tarczy w pikselach tekstury

const FACE_COLOR := Color(0.035, 0.04, 0.055)
const INK := Color(0.92, 0.9, 0.82)
const RED := Color(0.95, 0.18, 0.12)
const NEEDLE_COLOR := Color(1.0, 0.45, 0.08)
const DIGIT_COLOR := Color(1.0, 0.7, 0.3)

# --- konfiguracja (ustaw przed add_child) ---
var radius := 0.07               # m
var min_value := 0.0
var max_value := 100.0
var major_step := 10.0           # co ile duża kreska
var minor_per_major := 1         # ile małych kresek między dużymi
var label_every := 1             # podpis co n-tą dużą kreskę
var label_format := "%d"
var label_scale := 1.0           # mnożnik wartości w podpisie (np. 100 dla %)
var title := ""
var red_from := INF              # wartość, od której zaczyna się czerwone pole
var red_to := -INF               # ... i na której się kończy
var readout_digits := 0          # 0 = bez okienka
var readout_caption := ""
var has_lamp := false
var smoothing := 6.0             # bezwładność wskazówki (1/s)

var _value := 0.0
var _shown := 0.0
var _needle: Node3D
var _readout: Label3D
var _lamp_mat: StandardMaterial3D
var _face_mat: StandardMaterial3D


func _ready() -> void:
	_build()


## Ustawia wskazówkę (z bezwładnością). snap = bez animacji.
func set_value(v: float, snap := false) -> void:
	_value = clampf(v, min_value, max_value)
	if snap:
		_shown = _value
		_apply_needle()


func set_readout(n: int) -> void:
	if _readout:
		_readout.text = str(clampi(n, 0, int(pow(10, readout_digits)) - 1)).pad_zeros(readout_digits)


func set_lamp(on: bool) -> void:
	if _lamp_mat:
		_lamp_mat.albedo_color = RED if on else Color(0.18, 0.04, 0.03)


func _process(delta: float) -> void:
	_shown = lerpf(_shown, _value, 1.0 - exp(-smoothing * delta))
	_apply_needle()


func _frac(v: float) -> float:
	return (v - min_value) / (max_value - min_value)


func _apply_needle() -> void:
	# kąt od pionu, dodatni = przeciwnie do zegara (wokół +Z, w stronę lewej)
	_needle.rotation.z = deg_to_rad(SWEEP * 0.5 - SWEEP * _frac(_shown))


# ---------------------------------------------------------------- budowa

func _build() -> void:
	var r := radius
	var px := r / R_PX           # metrów na piksel tekstury

	# tarcza
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (2.0 * r * TEX / (2.0 * R_PX))
	var face := MeshInstance3D.new()
	face.mesh = quad
	_face_mat = StandardMaterial3D.new()
	_face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # podświetlana
	_face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_face_mat.alpha_scissor_threshold = 0.5
	_face_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_face_mat.disable_fog = true
	face.material_override = _face_mat
	add_child(face)
	_bake_face()

	# obręcz
	var bezel_mat := StandardMaterial3D.new()
	bezel_mat.albedo_color = Color(0.32, 0.33, 0.36)
	bezel_mat.metallic = 0.8
	bezel_mat.roughness = 0.35
	var ring := TorusMesh.new()
	ring.inner_radius = r * 0.98
	ring.outer_radius = r * 1.1
	ring.rings = 32
	ring.ring_segments = 8
	var bezel := MeshInstance3D.new()
	bezel.mesh = ring
	bezel.rotation_degrees = Vector3(90, 0, 0)
	bezel.material_override = bezel_mat
	add_child(bezel)
	# tył obudowy
	var back := CylinderMesh.new()
	back.top_radius = r * 1.08
	back.bottom_radius = r * 1.0
	back.height = r * 0.4
	back.radial_segments = 32
	var housing := MeshInstance3D.new()
	housing.mesh = back
	housing.rotation_degrees = Vector3(90, 0, 0)
	housing.position.z = -r * 0.21
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.08, 0.085, 0.1)
	housing.material_override = hmat
	add_child(housing)

	# wskazówka: pivot w środku, igła wzdłuż +Y
	var nmat := StandardMaterial3D.new()
	nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nmat.albedo_color = NEEDLE_COLOR
	nmat.disable_fog = true
	_needle = Node3D.new()
	_needle.position.z = r * 0.03
	add_child(_needle)
	var nlen := r * 0.86
	var nm := BoxMesh.new()
	nm.size = Vector3(r * 0.035, nlen + r * 0.2, r * 0.01)
	var needle := MeshInstance3D.new()
	needle.mesh = nm
	needle.position.y = (nlen - r * 0.2) * 0.5
	needle.material_override = nmat
	_needle.add_child(needle)
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = r * 0.09
	cap_mesh.bottom_radius = r * 0.09
	cap_mesh.height = r * 0.04
	cap_mesh.radial_segments = 16
	var cap := MeshInstance3D.new()
	cap.mesh = cap_mesh
	cap.rotation_degrees = Vector3(90, 0, 0)
	cap.position.z = r * 0.05
	cap.material_override = bezel_mat
	add_child(cap)

	# okienko z cyframi (tło jest narysowane na tarczy)
	if readout_digits > 0:
		_readout = Label3D.new()
		_readout.position = Vector3(0, -READOUT_Y * r, r * 0.02)
		_readout.pixel_size = r * READOUT_H / 64.0
		_readout.font_size = 64
		_readout.outline_size = 0
		_readout.modulate = DIGIT_COLOR
		_readout.double_sided = false
		add_child(_readout)
		set_readout(0)

	if has_lamp:
		var lm := SphereMesh.new()
		lm.radius = r * 0.07
		lm.height = r * 0.07
		lm.radial_segments = 12
		lm.rings = 6
		var lamp := MeshInstance3D.new()
		lamp.mesh = lm
		lamp.position = Vector3(0, -READOUT_Y * r, r * 0.02)
		_lamp_mat = StandardMaterial3D.new()
		_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_lamp_mat.disable_fog = true
		lamp.material_override = _lamp_mat
		add_child(lamp)
		set_lamp(false)

	set_value(_value, true)


const READOUT_Y := 0.62          # środek okienka, w promieniach pod osią
const READOUT_H := 0.2           # wysokość cyfr, w promieniach


func _bake_face() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(TEX, TEX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := _FacePainter.new()
	painter.g = self
	painter.size = Vector2(TEX, TEX)
	vp.add_child(painter)
	add_child(vp)
	_face_mat.albedo_texture = vp.get_texture()

	# Po narysowaniu: kopia do ImageTexture z mipmapami (ostra pod kątem)
	# i zwolnienie viewportu.
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img and not img.is_empty():
		img.generate_mipmaps()
		_face_mat.albedo_texture = ImageTexture.create_from_image(img)
		vp.queue_free()


class _FacePainter:
	extends Control
	var g: Gauge

	func _pt(c: Vector2, frac: float, rad: float) -> Vector2:
		var a := deg_to_rad(-Gauge.SWEEP * 0.5 + Gauge.SWEEP * frac)   # od pionu, zgodnie z zegarem
		return c + Vector2(sin(a), -cos(a)) * rad

	func _draw() -> void:
		var c := size * 0.5
		var font := ThemeDB.fallback_font
		draw_circle(c, Gauge.R_PX, Gauge.FACE_COLOR)

		# czerwone pole
		if g.red_to > g.red_from:
			var f0 := clampf(g._frac(g.red_from), 0.0, 1.0)
			var f1 := clampf(g._frac(g.red_to), 0.0, 1.0)
			var a0 := deg_to_rad(-Gauge.SWEEP * 0.5 + Gauge.SWEEP * f0 - 90.0)
			var a1 := deg_to_rad(-Gauge.SWEEP * 0.5 + Gauge.SWEEP * f1 - 90.0)
			draw_arc(c, Gauge.R_PX * 0.86, a0, a1, 48, Gauge.RED, Gauge.R_PX * 0.07, true)

		# kreski i podpisy
		var majors := int(round((g.max_value - g.min_value) / g.major_step))
		var steps := majors * (g.minor_per_major + 1)
		for i in steps + 1:
			var f := float(i) / steps
			var major := i % (g.minor_per_major + 1) == 0
			var r_in := Gauge.R_PX * (0.74 if major else 0.81)
			draw_line(_pt(c, f, r_in), _pt(c, f, Gauge.R_PX * 0.92), Gauge.INK, 7.0 if major else 3.0, true)
			var mi := i / (g.minor_per_major + 1)
			if major and mi % g.label_every == 0:
				var v := (g.min_value + mi * g.major_step) * g.label_scale
				var txt: String = g.label_format % v
				var fs := int(Gauge.R_PX * 0.2)
				var p := _pt(c, f, Gauge.R_PX * 0.55)
				draw_string(font, p + Vector2(-Gauge.R_PX * 0.3, fs * 0.36), txt,
						HORIZONTAL_ALIGNMENT_CENTER, Gauge.R_PX * 0.6, fs, Gauge.INK)

		# tytuł nad osią; zmniejszony, jeśli nie mieści się między podpisami
		if g.title != "":
			var max_w := Gauge.R_PX * 0.5
			var fs := int(Gauge.R_PX * 0.15)
			var w := font.get_string_size(g.title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if w > max_w:
				fs = int(fs * max_w / w)
			draw_string(font, c + Vector2(-max_w, -Gauge.R_PX * 0.22), g.title,
					HORIZONTAL_ALIGNMENT_CENTER, max_w * 2.0, fs, Gauge.INK.darkened(0.25))

		# okienko licznika
		if g.readout_digits > 0:
			var h := Gauge.R_PX * Gauge.READOUT_H * 1.35
			var w := Gauge.R_PX * Gauge.READOUT_H * 0.62 * g.readout_digits + Gauge.R_PX * 0.12
			var mid := c + Vector2(0, Gauge.R_PX * Gauge.READOUT_Y)
			draw_rect(Rect2(mid - Vector2(w, h) * 0.5, Vector2(w, h)), Color(0, 0, 0))
			draw_rect(Rect2(mid - Vector2(w, h) * 0.5, Vector2(w, h)), Gauge.INK.darkened(0.5), false, 3.0)
			if g.readout_caption != "":
				var fs := int(Gauge.R_PX * 0.11)
				draw_string(font, mid + Vector2(-Gauge.R_PX * 0.5, h * 0.5 + fs * 1.05), g.readout_caption,
						HORIZONTAL_ALIGNMENT_CENTER, Gauge.R_PX, fs, Gauge.INK.darkened(0.25))
