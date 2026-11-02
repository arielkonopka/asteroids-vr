class_name TitleScreen
extends Node3D
## Ekran startowy: tablica przed kokpitem (w układzie statku) z tytułem,
## rekordem, ostatnim wynikiem i skrótem sterowania. Skały dryfują w tle.

const EYE := Vector3.ZERO
const POS := Vector3(0.0, 0.02, -1.5)
const WIDTH := 1.25
const HEIGHT := 0.86

var _prompt: Label3D
var _scores: Label3D
var _t := 0.0


func _ready() -> void:
	transform = Transform3D(Basis.looking_at(EYE - POS, Vector3.UP, true), POS)

	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.02, 0.025, 0.04)
	bg_mat.disable_fog = true
	var q := QuadMesh.new()
	q.size = Vector2(WIDTH, HEIGHT)
	var bg := MeshInstance3D.new()
	bg.mesh = q
	bg.material_override = bg_mat
	add_child(bg)
	# ramka w kolorze wykończenia kokpitu
	var frame_mat := StandardMaterial3D.new()
	frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame_mat.albedo_color = Color(0.9, 0.45, 0.1)
	frame_mat.disable_fog = true
	for side in [[Vector3(0, HEIGHT * 0.5, 0), Vector3(WIDTH, 0.008, 0.004)],
			[Vector3(0, -HEIGHT * 0.5, 0), Vector3(WIDTH, 0.008, 0.004)],
			[Vector3(WIDTH * 0.5, 0, 0), Vector3(0.008, HEIGHT, 0.004)],
			[Vector3(-WIDTH * 0.5, 0, 0), Vector3(0.008, HEIGHT, 0.004)]]:
		var bm := BoxMesh.new()
		bm.size = side[1]
		var b := MeshInstance3D.new()
		b.mesh = bm
		b.position = side[0]
		b.material_override = frame_mat
		add_child(b)

	_label("ASTEROIDS VR", 0.30, 120, Color(1.0, 0.6, 0.15), 24)
	_label("a cockpit inside a three-dimensional torus", 0.205, 40, Color(0.7, 0.72, 0.8))
	_scores = _label("", 0.11, 52, Color(1.0, 0.8, 0.45))
	_label(
		"RIGHT stick — pitch & yaw\n" +
		"LEFT stick — roll     LEFT trigger — thrust     LEFT grip — brake\n" +
		"RIGHT trigger — fire     ≡ — pause\n\n" +
		"Power-ups (fly through the crystal):\n" +
		"S shield    3 triple shot    + extra life    B bomb\n" +
		"UFOs shoot back — listen for where they come from.",
		-0.1, 36, Color(0.82, 0.84, 0.9))
	_prompt = _label("", -0.36, 48, Color(0.4, 1.0, 0.5))


func _label(text: String, y: float, size: int, color: Color, outline := 0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.00075
	l.outline_size = outline
	l.outline_modulate = Color(0.25, 0.08, 0.0)
	l.modulate = color
	l.position = Vector3(0, y, 0.002)
	l.line_spacing = 4.0
	add_child(l)
	return l


func open(high: int, last: int, xr: bool) -> void:
	var txt := "HIGH SCORE  %06d" % high
	if last >= 0:
		txt += "        LAST SCORE  %06d" % last
	_scores.text = txt
	_prompt.text = "Pull the RIGHT TRIGGER to start" if xr else "SPACE — start"
	_t = 0.0
	visible = true


func _process(delta: float) -> void:
	if visible:
		_t += delta
		_prompt.modulate.a = 0.55 + 0.45 * sin(_t * 4.0)
