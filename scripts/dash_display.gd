extends SubViewport
class_name DashDisplay
## Live TFT dash for the R1: redraws the screen area of the bike's display texture with the
## current speed, RPM, gear, mode line and clock. Only re-renders when a shown value changes.
##
## The display mesh samples the photo flipped vertically, so the overlay is drawn flipped too.

const SCREEN_CENTER := Vector2(495, 323)      # centre of the TFT in the 1024x512 texture
const SCREEN_SIZE := Vector2(330, 128)        # active screen area (pixels)

var speed := 0.0
var rpm := 1300.0
var gear := 1
var _shown := Vector3(-1, -1, -1)
var _canvas: DashCanvas

func _init() -> void:
	size = Vector2i(1024, 512)
	transparent_bg = false
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_ONCE

func setup(photo: Texture2D) -> void:
	var bg := TextureRect.new()
	bg.texture = photo
	bg.size = Vector2(1024, 512)
	add_child(bg)
	_canvas = DashCanvas.new()
	_canvas.dash = self
	_canvas.size = Vector2(1024, 512)
	add_child(_canvas)

func set_values(kmh: float, r: float, g: int) -> void:
	speed = kmh
	rpm = r
	gear = g
	var key := Vector3(int(round(kmh)), int(r / 200.0), g)
	if key != _shown or fmod(Time.get_ticks_msec() / 1000.0, 0.25) < 0.02:
		_shown = key
		_canvas.queue_redraw()
		render_target_update_mode = SubViewport.UPDATE_ONCE

class DashCanvas extends Control:
	var dash: DashDisplay

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		var c := DashDisplay.SCREEN_CENTER
		var sz := DashDisplay.SCREEN_SIZE
		# Flip vertically about the screen centre (see class note).
		draw_set_transform(c, 0.0, Vector2(1, -1))
		var hw := sz.x * 0.5
		var hh := sz.y * 0.5
		draw_rect(Rect2(-hw, -hh, sz.x, sz.y), Color(0.01, 0.012, 0.015))
		var white := Color(0.93, 0.95, 0.97)
		var dim := Color(0.35, 0.37, 0.4)
		var red := Color(1.0, 0.16, 0.12)
		var rpm := dash.rpm
		var shift := rpm > 12900.0 and fmod(Time.get_ticks_msec() / 90.0, 2.0) < 1.0
		# --- tach: 28 segments rising left to right (R1 style), x1000 r/min ---
		var segs := 28
		var x0 := -hw + 10.0
		var w := sz.x - 20.0
		var seg_w := w / segs
		for i in segs:
			var v := (i + 1) * 500.0
			var hgt := lerpf(6.0, 26.0, pow(float(i) / (segs - 1), 1.4))
			var x := x0 + i * seg_w
			var y := -hh + 34.0 - hgt
			var col := dim
			if v <= rpm:
				col = red if v > 12500.0 else white
			if v > 12500.0 and v > rpm:
				col = Color(0.45, 0.08, 0.06)
			if shift:
				col = red
			draw_rect(Rect2(x + 1, y, seg_w - 2, hgt), col)
		for n: int in [4, 6, 8, 10, 12, 14]:
			var x := x0 + (n * 2 - 1) * seg_w + seg_w * 0.5
			draw_string(f, Vector2(x - 6, -hh + 47), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, red if n >= 13 else white)
		draw_string(f, Vector2(-hw + 8, -hh + 47), "x1000r/min", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dim)
		# --- speed ---
		var sp := str(int(round(dash.speed)))
		var fs := 46
		var tw := f.get_string_size(sp, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(18 - tw, hh - 26), sp, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white)
		draw_string(f, Vector2(22, hh - 30), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, white)
		# --- gear indicator ---
		var gb := Rect2(hw - 74, -hh + 54, 52, 52)
		draw_rect(gb, Color(0.6, 0.62, 0.66), false, 2.0)
		var gtxt := "N" if dash.gear <= 0 else str(dash.gear)
		var gcol := Color(0.2, 0.95, 0.35) if dash.gear <= 0 else white
		var gw := f.get_string_size(gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x
		draw_string(f, Vector2(gb.position.x + (gb.size.x - gw) * 0.5, gb.end.y - 9), gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 42, gcol)
		# --- left info column ---
		draw_string(f, Vector2(-hw + 10, -hh + 72), "C.TEMP  92°C", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, white)
		draw_string(f, Vector2(-hw + 10, -hh + 88), "A.TEMP  24°C", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, white)
		# --- bottom mode line + clock ---
		draw_rect(Rect2(-hw + 6, hh - 18, sz.x - 12, 14), Color(0.12, 0.13, 0.15))
		draw_string(f, Vector2(-hw + 10, hh - 7), "MODE-A  PWR 1  TCS 3  SCS 2  EBM 1", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, white)
		var t := Time.get_time_dict_from_system()
		draw_string(f, Vector2(hw - 42, hh - 7), "%d:%02d" % [t.hour, t.minute], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, white)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
