extends Node
class_name BikeAudio
## Procedurally synthesised audio: crossplane inline-4 engine loops (cross-faded and pitched by RPM),
## wind, tyre roar, rail scrape and one-shots (horn, whoosh, crash, shift, bonus).

const SR := 22050
# RPM at which each engine loop is rendered.
const ENGINE_RPMS := [1300.0, 3200.0, 5500.0, 8000.0, 10500.0, 13000.0, 15000.0]

var engine_players: Array[AudioStreamPlayer] = []
var wind: AudioStreamPlayer
var roar: AudioStreamPlayer
var scrape: AudioStreamPlayer
var rain_player: AudioStreamPlayer
var raining := false
var oneshots: Array[AudioStreamPlayer] = []
var _horn: AudioStreamWAV
var _whoosh: AudioStreamWAV
var _crash: AudioStreamWAV
var _shift: AudioStreamWAV
var _bonus: AudioStreamWAV
var _engine_bus := -1
var _wind_bus := -1
var _lp_engine: AudioEffectLowPassFilter
var _lp_wind: AudioEffectLowPassFilter
var _throttle_s := 0.0
var _paused := false
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 1234
	_engine_bus = _make_bus("Engine")
	_lp_engine = AudioEffectLowPassFilter.new()
	_lp_engine.cutoff_hz = 3000.0
	_lp_engine.resonance = 0.6
	AudioServer.add_bus_effect(_engine_bus, _lp_engine)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -10.0
	comp.ratio = 3.0
	AudioServer.add_bus_effect(_engine_bus, comp)
	_wind_bus = _make_bus("Wind")
	_lp_wind = AudioEffectLowPassFilter.new()
	_lp_wind.cutoff_hz = 800.0
	AudioServer.add_bus_effect(_wind_bus, _lp_wind)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(Game.sfx_volume, 0.001)))
	for r in ENGINE_RPMS:
		var p := AudioStreamPlayer.new()
		p.stream = engine_stream(r, rng)
		p.bus = "Engine"
		p.volume_db = -80.0
		add_child(p)
		p.play()
		engine_players.append(p)
	wind = _loop_player(render_noise(2.0, 0.0, 1.0), "Wind")
	roar = _loop_player(render_noise(1.5, 0.92, 0.6), "Master")
	scrape = _loop_player(render_scrape(), "Master")
	rain_player = _loop_player(render_noise(2.5, 0.35, 0.9), "Master")
	_horn = render_horn()
	_whoosh = render_whoosh()
	_crash = render_crash()
	_shift = render_shift()
	_bonus = render_bonus()
	for i in 4:
		var o := AudioStreamPlayer.new()
		add_child(o)
		oneshots.append(o)

func _make_bus(n: String) -> int:
	var idx := AudioServer.get_bus_index(n)
	if idx >= 0:
		# Clear old effects from a previous run.
		while AudioServer.get_bus_effect_count(idx) > 0:
			AudioServer.remove_bus_effect(idx, 0)
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, n)
	AudioServer.set_bus_send(idx, "Master")
	return idx

func _loop_player(stream: AudioStreamWAV, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p

func set_paused(p: bool) -> void:
	_paused = p
	for c in get_children():
		if c is AudioStreamPlayer:
			c.stream_paused = p

func update(r: Rider, dt: float) -> void:
	if _paused:
		return
	var rpm := r.rpm
	var thr := r.throttle if not r.is_crashed else 0.0
	if r.is_crashed:
		rpm = lerpf(rpm, 1300.0, 0.0)
	_throttle_s = lerpf(_throttle_s, thr, 1.0 - exp(-12.0 * dt))
	# Cross-fade between the two loops bracketing the current RPM and pitch them to match.
	var n := ENGINE_RPMS.size()
	var i := 0
	while i < n - 2 and rpm > ENGINE_RPMS[i + 1]:
		i += 1
	var r0: float = ENGINE_RPMS[i]
	var r1: float = ENGINE_RPMS[i + 1]
	var x := clampf((rpm - r0) / (r1 - r0), 0.0, 1.0)
	var load_db := lerpf(-9.0, 0.0, _throttle_s)
	if r.is_crashed:
		load_db = -14.0 - r.crash_time * 6.0
	for k in n:
		var p := engine_players[k]
		var g := 0.0
		if k == i:
			g = cos(x * PI * 0.5)
		elif k == i + 1:
			g = sin(x * PI * 0.5)
		if g < 0.001:
			p.volume_db = -80.0
		else:
			p.volume_db = linear_to_db(g) + load_db - 4.0
		p.pitch_scale = clampf(rpm / ENGINE_RPMS[k], 0.5, 2.0)
	_lp_engine.cutoff_hz = lerpf(1400.0, 7000.0, _throttle_s) + rpm * 0.15
	var sp := r.v
	wind.volume_db = linear_to_db(clampf(sp / 85.0, 0.0, 1.0) * 0.9 + 0.001) - 3.0
	wind.pitch_scale = 0.8 + sp / 120.0
	_lp_wind.cutoff_hz = 400.0 + sp * 45.0
	roar.volume_db = linear_to_db(clampf(sp / 60.0, 0.0, 1.0) * 0.35 + 0.001) - 6.0
	roar.pitch_scale = 0.7 + sp / 90.0
	scrape.volume_db = -80.0 if r.scrape < 0.3 else linear_to_db(r.scrape * 0.6)
	if raining:
		rain_player.volume_db = -11.0
		rain_player.pitch_scale = 1.0
		# Tyres hissing through water.
		roar.volume_db = linear_to_db(clampf(sp / 50.0, 0.0, 1.0) * 0.7 + 0.001) - 4.0
		roar.pitch_scale = 1.1 + sp / 70.0
	else:
		rain_player.volume_db = -80.0

func _play(stream: AudioStreamWAV, vol_db: float, pitch: float = 1.0) -> void:
	for o in oneshots:
		if not o.playing:
			o.stream = stream
			o.volume_db = vol_db
			o.pitch_scale = pitch
			o.play()
			return

func play_horn() -> void:
	_play(_horn, -7.0, rng.randf_range(0.85, 1.15))

func play_whoosh(speed: float) -> void:
	_play(_whoosh, -4.0, clampf(0.8 + speed / 120.0, 0.8, 1.5))

func play_crash() -> void:
	_play(_crash, 0.0)

func on_shift(_gear: int) -> void:
	_play(_shift, -10.0, rng.randf_range(0.95, 1.05))

func play_bonus() -> void:
	_play(_bonus, -6.0)

# ------------------------------------------------------------------ synthesis

static func _wav(data: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		var v := clampi(int(clampf(data[i], -1.0, 1.0) * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w

static func engine_path(rpm: float) -> String:
	return "res://assets/audio/engine_%d.res" % int(rpm)

## Loads the pre-baked engine loop if present (fast startup on phones), otherwise synthesises it.
static func engine_stream(rpm: float, r: RandomNumberGenerator) -> AudioStreamWAV:
	var path := engine_path(rpm)
	if ResourceLoader.exists(path):
		return load(path)
	return _wav(render_engine_samples(rpm, r), true)

## Bakes all engine loops to res://assets/audio (run with the --bake-audio dev flag).
static func bake_all() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/audio")
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	for rpm in ENGINE_RPMS:
		var w := _wav(render_engine_samples(rpm, r), true)
		var err := ResourceSaver.save(w, engine_path(rpm))
		print("[bake] ", engine_path(rpm), " samples=", w.data.size() / 2, " err=", err)

## Offline audio check (--audiotest): renders every sound, asserts finite samples, prints peak/RMS.
static func self_test() -> bool:
	var ok := true
	var r := RandomNumberGenerator.new()
	r.seed = 1
	var items := {}
	for rpm in ENGINE_RPMS:
		items["engine_%d" % int(rpm)] = _wav(render_engine_samples(rpm, r), true)
	items["wind"] = render_noise(2.0, 0.0, 1.0)
	items["roar"] = render_noise(1.5, 0.92, 0.6)
	items["scrape"] = render_scrape()
	items["horn"] = render_horn()
	items["whoosh"] = render_whoosh()
	items["crash"] = render_crash()
	items["shift"] = render_shift()
	items["bonus"] = render_bonus()
	for k in items:
		var w: AudioStreamWAV = items[k]
		var n := w.data.size() / 2
		var peak := 0.0
		var sum := 0.0
		var seam := 0.0
		for i in n:
			var v := w.data.decode_s16(i * 2) / 32768.0
			if is_nan(v) or is_inf(v):
				ok = false
			peak = maxf(peak, absf(v))
			sum += v * v
		if w.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			seam = absf(w.data.decode_s16((n - 1) * 2) - w.data.decode_s16(0)) / 32768.0
		var rms := sqrt(sum / maxf(n, 1))
		print("[audio] %-13s len=%.2fs peak=%.2f rms=%.3f (%.1f dBFS) loop_seam_jump=%.3f" % [k, n / float(SR), peak, rms, linear_to_db(maxf(rms, 1e-6)), seam])
		if peak < 0.05 or peak > 1.0:
			ok = false
	print("[audio] self-test ", "PASS" if ok else "FAIL")
	return ok

## One engine loop at `rpm`. Crossplane I4: four firings per 720° at 0/270/450/540 degrees.
func render_engine(rpm: float) -> AudioStreamWAV:
	var data := render_engine_samples(rpm, rng)
	return _wav(data, true)

static func render_engine_samples(rpm: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var f_cycle := rpm / 120.0                 # engine cycles (720°) per second
	var cycles := maxi(4, int(round(f_cycle * 0.6)))
	var length := int(round(cycles * SR / f_cycle))
	var cyc_len := float(length) / cycles     # samples per cycle (exactly periodic)
	var buf := PackedFloat32Array()
	buf.resize(length)
	var fires := [0.0, 0.375, 0.625, 0.75]
	# Exhaust resonances (fixed formants give the "engine" character).
	var res := [[95.0 + rpm * 0.004, 1.0], [240.0 + rpm * 0.01, 0.6], [520.0, 0.35], [1150.0, 0.18], [2300.0, 0.08]]
	var decay := clampf(0.010 - rpm * 0.0000004, 0.0035, 0.01)  # seconds
	var win := int(decay * 5.0 * SR)
	var amps := []
	for c in cycles:
		var row := []
		for f in fires.size():
			row.append(1.0 + r.randf_range(-0.18, 0.18))
		amps.append(row)
	for c in cycles:
		for f in fires.size():
			var start := (c + float(fires[f])) * cyc_len
			var a: float = amps[c][f]
			var phase_j := r.randf() * TAU
			for k in win:
				var t := k / float(SR)
				var env := exp(-t / decay) * (1.0 - exp(-t / 0.0004))
				var v := 0.0
				for rr in res:
					v += sin(TAU * rr[0] * t + phase_j * 0.2) * rr[1]
				var idx := int(start) + k
				buf[idx % length] += v * env * a
	# Low "crank" hum at the cycle frequency and its 2nd harmonic for body.
	for i in length:
		var ph := TAU * i / cyc_len
		buf[i] += 0.22 * sin(ph * 2.0) + 0.12 * sin(ph * 4.0 + 0.5)
	# Mechanical/intake noise, cross-faded to loop seamlessly.
	var noise := PackedFloat32Array()
	noise.resize(length)
	var lp := 0.0
	for i in length:
		lp += (r.randf_range(-1, 1) - lp) * 0.35
		noise[i] = lp
	for i in length:
		buf[i] += noise[i] * 0.12 * (1.0 + 0.5 * sin(TAU * i / cyc_len * 4.0))
	# Normalise and soft-clip for grit.
	var peak := 0.0001
	for i in length:
		peak = maxf(peak, absf(buf[i]))
	for i in length:
		buf[i] = tanh(buf[i] / peak * 1.6) * 0.75
	return buf

## Filtered noise loop. `lowness` 0..1 (higher = darker), seamless via crossfade.
static func render_noise(seconds: float, lowness: float, amp: float) -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = int(seconds * 1000 + lowness * 77)
	var n := int(seconds * SR)
	var fade := int(0.2 * SR)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var lp := 0.0
	var lp2 := 0.0
	var k := 1.0 - lowness * 0.97
	for i in n + fade:
		lp += (r.randf_range(-1, 1) - lp) * k
		lp2 += (lp - lp2) * k
		raw[i] = lp2
	var out := PackedFloat32Array()
	out.resize(n)
	var peak := 0.0001
	for i in n:
		var v := raw[i]
		if i < fade:
			var t := float(i) / fade
			v = raw[i] * t + raw[n + i] * (1.0 - t)
		out[i] = v
		peak = maxf(peak, absf(v))
	for i in n:
		out[i] = out[i] / peak * amp * 0.8
	return _wav(out, true)

static func render_scrape() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var n := int(0.8 * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var w := r.randf_range(-1, 1)
		var hp := w - prev
		prev = w
		var t := float(i) / SR
		out[i] = hp * 0.35 * (0.7 + 0.3 * sin(TAU * 37.0 * t)) + sin(TAU * 2900.0 * t) * 0.06 * r.randf()
	# loop crossfade
	var fade := 800
	for i in fade:
		var a := float(i) / fade
		out[i] = out[i] * a + out[n - fade + i] * (1.0 - a)
	return _wav(out.slice(0, n - fade), true)

static func render_horn() -> AudioStreamWAV:
	var n := int(0.55 * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SR
		var env := minf(t / 0.02, 1.0) * minf((0.55 - t) / 0.06, 1.0)
		var v := 0.0
		for f in [415.0, 520.0]:
			var ph := fmod(t * f, 1.0)
			v += (1.0 if ph < 0.45 else -1.0) * 0.5
			v += sin(TAU * f * 2.0 * t) * 0.15
		out[i] = tanh(v * 0.9) * env * 0.5
	return _wav(out, false)

static func render_whoosh() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var dur := 0.7
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var bp := 0.0
	for i in n:
		var t := float(i) / SR
		var x := t / dur
		var env := pow(sin(PI * pow(x, 0.7)), 2.0)
		var k := 0.05 + 0.4 * env
		lp += (r.randf_range(-1, 1) - lp) * k
		bp += (lp - bp) * 0.3
		out[i] = (lp - bp) * env * 1.6
	return _wav(out, false)

static func render_crash() -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var dur := 1.6
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var hits := [0.0, 0.12, 0.31, 0.55, 0.8]
	for i in n:
		var t := float(i) / SR
		lp += (r.randf_range(-1, 1) - lp) * 0.25
		var v := lp * exp(-t * 2.2) * 0.8
		v += sin(TAU * 55.0 * t) * exp(-t * 9.0) * 0.9
		for h in hits:
			var dt: float = t - h
			if dt > 0.0 and dt < 0.4:
				v += (sin(TAU * 1250.0 * dt) + sin(TAU * 1873.0 * dt) * 0.6 + sin(TAU * 3120.0 * dt) * 0.3) * exp(-dt * 14.0) * 0.35
		out[i] = tanh(v * 1.4) * 0.85
	return _wav(out, false)

static func render_shift() -> AudioStreamWAV:
	var n := int(0.08 * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SR
		out[i] = (sin(TAU * 180.0 * t) * 0.6 + sin(TAU * 950.0 * t) * 0.3) * exp(-t * 60.0)
	return _wav(out, false)

static func render_bonus() -> AudioStreamWAV:
	var n := int(0.6 * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes := [880.0, 1108.7, 1318.5]
	for i in n:
		var t := float(i) / SR
		var v := 0.0
		for k in notes.size():
			var st: float = k * 0.09
			if t > st:
				var dt: float = t - st
				v += sin(TAU * notes[k] * dt) * exp(-dt * 6.0) * 0.3
		out[i] = v
	return _wav(out, false)
