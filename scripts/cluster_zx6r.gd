extends Control
class_name ClusterZX6R
## ZX-6R instrument cluster, drawn into the dash texture: warning-light column on the left, the big
## analog tachometer (0-4k compressed along the bottom, linear up to 18k, red from 16k) with a
## silver needle, the GEAR / CLOCK window on the dial's right edge, and the backlit LCD on the right
## (trip, odometer, big 7-segment speed, fuel bar, mode line). An amber shift lamp flashes at the
## redline.
##
## Layout is in texture pixels of a 1024 x 452 canvas, which BikeVisual projects flat onto the
## model's three dash faces (left panel, round dial, LCD panel), so everything lands in its slot.

var dash: DashDisplay

const W := 1024.0
const H := 452.0
const DIAL_C := Vector2(428, 229)
const DIAL_R := 206.0
const LCD := Rect2(674, 46, 340, 330)
const GEAR_BOX := Rect2(505, 160, 98, 172)
const BEZEL := Color(0.06, 0.065, 0.07)
const FACE := Color(0.035, 0.037, 0.04)
const LCD_BG := Color(0.80, 0.84, 0.84)
const LCD_INK := Color(0.05, 0.06, 0.07)
const LCD_GHOST := Color(0.70, 0.74, 0.74)
const RED := Color(0.95, 0.15, 0.12)

## Needle angle (screen radians, y down) for an rpm: 0-4k squeezed into the first 45 degrees.
static func rpm_angle(r: float) -> float:
	var a: float
	if r < 4000.0:
		a = 75.0 + r / 4000.0 * 45.0
	else:
		a = 120.0 + (minf(r, 18500.0) - 4000.0) / 14000.0 * 200.0
	return deg_to_rad(a)

func _draw() -> void:
	var f := ThemeDB.fallback_font
	var t := Time.get_ticks_msec() / 1000.0
	draw_rect(Rect2(0, 0, W, H), BEZEL)
	_draw_warning_panel(f)
	_draw_lcd(f, t)
	_draw_dial(f)
	_draw_gear_box(f)
	# Amber shift lamp under the LCD (flashes at the redline).
	var shift := dash.rpm > dash.redline - 600.0 and fmod(t * 8.0, 2.0) < 1.0
	var lamp := Rect2(LCD.position.x + 92, LCD.end.y + 18, 46, 26)
	draw_rect(lamp, Color(1.0, 0.45, 0.05) if shift else Color(0.28, 0.12, 0.04))
	if shift:
		draw_rect(lamp.grow(5), Color(1.0, 0.5, 0.1, 0.25))

# ------------------------------------------------------------------ left warning lights

func _draw_warning_panel(f: Font) -> void:
	draw_rect(Rect2(14, 40, 200, 372), FACE)
	var x := 40.0
	var lights := [
		["<", Color(0.15, 0.9, 0.3), false],            # turn signal
		["KTRC", Color(1.0, 0.55, 0.1), false],
		["OIL", Color(0.95, 0.2, 0.15), false],
		["HI", Color(0.25, 0.5, 1.0), true],            # high beam: on at night is plausible; keep lit dim
		["N", Color(0.2, 1.0, 0.35), dash.gear <= 0],
		["ABS", Color(1.0, 0.6, 0.1), false],
		["FI", Color(1.0, 0.6, 0.1), false],
	]
	for i in lights.size():
		var l: Array = lights[i]
		var y := 62.0 + i * 48.0
		var col: Color = l[1]
		var on: bool = l[2]
		var c := col if on else col.darkened(0.82)
		draw_rect(Rect2(x, y, 64, 36), Color(0.02, 0.02, 0.025))
		draw_string(f, Vector2(x + 4, y + 27), l[0], HORIZONTAL_ALIGNMENT_CENTER, 56, 20 if String(l[0]).length() < 4 else 15, c)
	# The two round select buttons.
	for by in [150.0, 322.0]:
		draw_circle(Vector2(150, by), 24, Color(0.015, 0.015, 0.018))
		draw_arc(Vector2(150, by), 24, 0, TAU, 32, Color(0.2, 0.21, 0.23), 2.0)

# ------------------------------------------------------------------ tachometer

func _draw_dial(f: Font) -> void:
	var c := DIAL_C
	# Chrome bezel ring + face.
	draw_circle(c, DIAL_R + 10, Color(0.32, 0.33, 0.35))
	draw_circle(c, DIAL_R + 4, Color(0.12, 0.125, 0.13))
	draw_circle(c, DIAL_R, FACE)
	var red_from := dash.redline
	# Red band along the rim from the redline to 18k.
	var a0 := rpm_angle(red_from)
	var a1 := rpm_angle(18000.0)
	draw_arc(c, DIAL_R - 9, a0, a1, 24, RED, 10.0)
	# Ticks every 500 rpm, labels every 1000 (1-4) / 2000 (4-18).
	var r := 0.0
	while r <= 18000.0:
		var a := rpm_angle(r)
		var dir := Vector2(cos(a), sin(a))
		var major := int(r) % 1000 == 0
		var col := RED if r >= red_from else Color(0.93, 0.94, 0.95)
		var l_in := DIAL_R - (34.0 if major else 22.0)
		if r < 4000.0 and not major:
			l_in = DIAL_R - 18.0
		draw_line(c + dir * l_in, c + dir * (DIAL_R - 6.0), col, 5.0 if major else 2.5, true)
		var label := ""
		if r < 4000.0 and major:
			label = str(int(r / 1000.0))
		elif int(r) % 2000 == 0 and r >= 4000.0:
			label = str(int(r / 1000.0))
		if label != "":
			var fs := 22 if r < 4000.0 else 38
			var p := c + dir * (DIAL_R - (58.0 if r < 4000.0 else 74.0))
			var sz := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(f, p + Vector2(-sz.x * 0.5, sz.y * 0.32), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		r += 500.0
	draw_string(f, c + Vector2(-30, -48), "x1000", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.75, 0.76, 0.78))
	draw_string(f, c + Vector2(4, -30), "r/min", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.76, 0.78))
	# Needle: silver blade with a dark counterweight, black hub cap.
	var na := rpm_angle(dash.rpm)
	var nd := Vector2(cos(na), sin(na))
	var np := Vector2(-nd.y, nd.x)
	var tip := c + nd * (DIAL_R - 14.0)
	var tail := c - nd * 34.0
	draw_colored_polygon(PackedVector2Array([tail + np * 9.0, c + np * 7.0, tip + np * 1.5, tip - np * 1.5, c - np * 7.0, tail - np * 9.0]), Color(0.86, 0.88, 0.9))
	draw_line(c + nd * 40.0, tip, Color(1, 1, 1), 2.0, true)
	draw_circle(c, 30, Color(0.02, 0.02, 0.022))
	draw_arc(c, 30, 0, TAU, 32, Color(0.25, 0.26, 0.28), 2.0)

# ------------------------------------------------------------------ gear / clock window

func _draw_gear_box(f: Font) -> void:
	var g := GEAR_BOX
	draw_rect(g.grow(5), Color(0.2, 0.21, 0.22))
	draw_rect(g, LCD_BG)
	draw_string(f, g.position + Vector2(8, 21), "GEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, LCD_INK)
	var txt := "N" if dash.gear <= 0 else str(dash.gear)
	if txt == "N":
		draw_string(f, g.position + Vector2(22, 110), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 80, LCD_INK)
	else:
		_seg_digit(int(txt), Rect2(g.position + Vector2(24, 30), Vector2(52, 88)), 11.0)
	draw_string(f, g.position + Vector2(8, 138), "CLOCK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LCD_INK)
	var tm := Time.get_time_dict_from_system()
	draw_string(f, g.position + Vector2(8, 164), "%d:%02d" % [tm.hour, tm.minute], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, LCD_INK)

# ------------------------------------------------------------------ LCD

func _draw_lcd(f: Font, _t: float) -> void:
	var l := LCD
	draw_rect(l.grow(6), Color(0.2, 0.21, 0.22))
	draw_rect(l, LCD_BG)
	var x0 := l.position.x
	var y0 := l.position.y
	# Top line: trip / odometer.
	draw_string(f, Vector2(x0 + 70, y0 + 34), "TRIP A", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, LCD_INK)
	_seg_number("%.1f" % fmod(dash.trip_km, 1000.0), Vector2(l.end.x - 46, y0 + 14), Vector2(20, 34), 5.0, LCD_INK)
	draw_string(f, Vector2(l.end.x - 44, y0 + 66), "km", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LCD_INK)
	# Fuel bar (left edge): F at top, E at the bottom.
	draw_string(f, Vector2(x0 + 9, y0 + 28), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LCD_INK)
	draw_string(f, Vector2(x0 + 9, y0 + 222), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LCD_INK)
	for i in 6:
		var on := i < 5
		draw_rect(Rect2(x0 + 8, y0 + 36 + i * 28, 14, 21), LCD_INK if on else LCD_GHOST)
	# Big speed: up to three 7-segment digits, right-aligned, ghost 8s behind like a real LCD.
	var sp := clampi(int(round(dash.speed)), 0, 399)
	var digits := str(sp)
	var dw := 60.0
	var dh := 120.0
	var right := l.end.x - 92.0
	for k in 3:
		var dx := right - (k + 1) * (dw + 12.0)
		var rect := Rect2(Vector2(dx, y0 + 82), Vector2(dw, dh))
		_seg_digit(8, rect, 12.0, LCD_GHOST)
		var idx := digits.length() - 1 - k
		if idx >= 0:
			_seg_digit(int(digits[idx]), rect, 12.0, LCD_INK)
	draw_string(f, Vector2(l.end.x - 86, y0 + 200), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, LCD_INK)
	# Mode line + odometer.
	draw_line(Vector2(x0 + 70, y0 + 232), Vector2(l.end.x - 14, y0 + 232), LCD_INK, 2.0)
	draw_string(f, Vector2(x0 + 70, y0 + 256), "POWER  KTRC  KQS", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, LCD_INK)
	draw_string(f, Vector2(x0 + 76, y0 + 306), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, LCD_INK)
	draw_string(f, Vector2(x0 + 128, y0 + 306), "2", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, LCD_INK)
	draw_string(f, Vector2(x0 + 168, y0 + 296), "ODO", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LCD_INK)
	_seg_number(str(int(dash.odo_km)), Vector2(l.end.x - 46, y0 + 274), Vector2(18, 32), 4.5, LCD_INK)

## Right-aligned 7-segment number ('.' allowed) ending at `right_top`.x.
func _seg_number(s: String, right_top: Vector2, digit: Vector2, th: float, col: Color) -> void:
	var x := right_top.x
	for i in range(s.length() - 1, -1, -1):
		var ch := s[i]
		if ch == ".":
			draw_rect(Rect2(x - th * 1.6, right_top.y + digit.y - th, th, th), col)
			x -= th * 2.2
			continue
		x -= digit.x
		_seg_digit(int(ch), Rect2(Vector2(x, right_top.y), digit), th, col)
		x -= digit.x * 0.35

const SEGS := [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F]

## One 7-segment digit (slightly slanted, like the Kawasaki LCD).
func _seg_digit(d: int, r: Rect2, th: float, col: Color = LCD_INK) -> void:
	var m: int = SEGS[clampi(d, 0, 9)]
	var x0 := r.position.x
	var y0 := r.position.y
	var w := r.size.x
	var h := r.size.y
	var hh := h * 0.5
	var slant := w * 0.12
	var sk := func(p: Vector2) -> Vector2: return Vector2(p.x + slant * (1.0 - (p.y - y0) / h), p.y)
	var hseg := func(y: float) -> PackedVector2Array:
		return PackedVector2Array([sk.call(Vector2(x0 + th * 0.6, y)), sk.call(Vector2(x0 + th, y - th * 0.5)), sk.call(Vector2(x0 + w - th, y - th * 0.5)),
			sk.call(Vector2(x0 + w - th * 0.6, y)), sk.call(Vector2(x0 + w - th, y + th * 0.5)), sk.call(Vector2(x0 + th, y + th * 0.5))])
	var vseg := func(x: float, ya: float, yb: float) -> PackedVector2Array:
		return PackedVector2Array([sk.call(Vector2(x, ya + th * 0.6)), sk.call(Vector2(x + th * 0.5, ya + th)), sk.call(Vector2(x + th * 0.5, yb - th)),
			sk.call(Vector2(x, yb - th * 0.6)), sk.call(Vector2(x - th * 0.5, yb - th)), sk.call(Vector2(x - th * 0.5, ya + th))])
	var segs := [
		hseg.call(y0 + th * 0.5),                         # a
		vseg.call(x0 + w - th * 0.5, y0, y0 + hh),        # b
		vseg.call(x0 + w - th * 0.5, y0 + hh, y0 + h),    # c
		hseg.call(y0 + h - th * 0.5),                     # d
		vseg.call(x0 + th * 0.5, y0 + hh, y0 + h),        # e
		vseg.call(x0 + th * 0.5, y0, y0 + hh),            # f
		hseg.call(y0 + hh),                               # g
	]
	for i in 7:
		if m & (1 << i):
			draw_colored_polygon(segs[i], col)
