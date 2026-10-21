class_name AudioSystem
extends Node
## Every sound, synthesised (src/systems/audio.js): there are no audio files
## to ship. The browser build plays a Web Audio graph per sound; here each
## sound is rendered once into a sample buffer by the same recipe
## (oscillators, noise, filters, the same envelopes) and then replayed.
## Sounds with a random part keep a few rendered variants.
## Three buses, as the Settings sliders: master, effects and ambience.

const RATE := 22050 ## effects
const AMB_RATE := 11025 ## the wind and rumble loops (nothing high in them)
const VOICES := 16
const VARIANTS := 4
const GROWL := {"brute": [70, 0.5], "hound": [170, 0.25], "archer": [220, 0.2], "seer": [95, 0.45]}

var game
var started := false
var cache := {} ## recipe key -> AudioStreamWAV
var voices: Array = [] ## AudioStreamPlayer pool
var next_voice := 0
var wind: AudioStreamPlayer
var rumble: AudioStreamPlayer
var rumble_level := 0.0
var next_crow := 6.0
var next_bell := 18.0
var next_creak := 10.0
var rng := RandomNumberGenerator.new()
var warm: Array = [] ## sounds still to render ahead of need, one per frame
var warming := false


func _init(g) -> void:
	game = g
	name = "Audio"


## Starts the buses, the ambient loops and the event hooks. A web export
## unlocks sound on the first click or key, as the browser build does.
func start() -> void:
	if started:
		return
	started = true
	for bus in ["Effects", "Ambience"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)
	apply_volumes()
	game.events.on("settingsChanged", func(e):
		if str(e.get("id", "")).begins_with("vol"):
			apply_volumes())
	wind = _loop(_wind(), "Ambience")
	rumble = _loop(_rumble(), "Ambience")
	rumble.volume_db = -80.0
	_bind()
	# the slow ones (bells, chimes) are made ahead, so their first ring
	# does not stall a frame
	warm = [func(): bell(1, 880), func(): bell(1, 440), func(): bell(1, 660), func(): chime([392, 523, 659], 0.25),
		func(): chime([392, 494, 587, 784], 0.22), func(): chime([660, 990], 0.12), func(): chime([330, 415], 0.15)]
	for i in VARIANTS:
		warm.append(func(): bell(1, 180 + i * 10, "Ambience"))


func _loop(s: AudioStreamWAV, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	add_child(p)
	p.play()
	return p


## the Settings sliders (percent); loudness follows the square, as ears do
func apply_volumes() -> void:
	var st = game.settings
	for b in [["Master", "volMaster"], ["Effects", "volEffects"], ["Ambience", "volAmbience"]]:
		var v: float = pow(float(st.get_value(b[1])) / 100.0, 2)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(b[0]), linear_to_db(maxf(v, 0.00001)))
	if game.hud:
		game.hud.set_muted(float(st.get_value("volMaster")) == 0)


func _bind() -> void:
	var ev = game.events
	ev.on("playerSwing", func(_e): whoosh(0.18, 900))
	ev.on("enemyHit", func(e):
		if e.get("kind") != "strike":
			return
		impact()
		if e.get("crit"):
			thud(90, 0.3)) # a crit lands with a deeper crunch
	ev.on("burst", func(_e): shield_break())
	ev.on("playerBrace", func(_e): thud(180, 0.12))
	ev.on("braceBlock", func(_e):
		impact()
		bell(0.12, 660))
	ev.on("corpseLooted", func(_e): coins())
	ev.on("enemyWindup", func(e):
		var g: Array = GROWL.get(e.enemy.type, [120, 0.35])
		growl(g[0], g[1]))
	ev.on("playerHurt", func(_e): thud(110, 0.25))
	ev.on("enemyDefeated", func(e): death(e.enemy.type == "brute"))
	ev.on("lootCollected", func(_e): chime([660, 990], 0.12))
	ev.on("coins", func(_e): coins())
	ev.on("levelUp", func(_e): chime([392, 523, 659], 0.25))
	ev.on("shrineRest", func(_e): bell(0.25, 440))
	ev.on("draught", func(_e): chime([330, 415], 0.15))
	ev.on("playerDied", func(_e): growl(55, 1.4))
	ev.on("playerLunge", func(_e): whoosh(0.3, 700))
	ev.on("graveSlam", func(_e):
		thud(60, 0.6)
		shield_break())
	ev.on("itemDropped", func(_e): thud(220, 0.12))
	# Mara's hammer: a short metallic ring, quieter with distance
	ev.on("anvilStrike", func(e):
		var p: Vector3 = game.player.position
		var d := U.hyp(p.x - e.x, p.z - e.z)
		if d < 22:
			bell(0.05 * maxf(0, 1 - d / 22), 880))
	ev.on("questComplete", func(_e): chime([392, 494, 587, 784], 0.22))


# ------------------------------------------------------------- playback
## Plays a rendered sound (made the first time it is asked for) at a level.
func _play(key: String, make: Callable, level := 1.0, bus := "Effects") -> void:
	if not started or level <= 0:
		return
	var s: AudioStreamWAV = cache.get(key)
	if s == null:
		s = _wav(make.call(), RATE)
		cache[key] = s
	if warming:
		return
	var p: AudioStreamPlayer = voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	p.stream = s
	p.bus = bus
	p.volume_db = linear_to_db(level)
	p.play()


func _variant() -> int:
	return rng.randi() % VARIANTS


static func _wav(buf: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1, 1) * 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


# --------------------------------------------------------------- synthesis
## Web Audio's envelope: from silence, exponentially up to `peak` over
## `attack`, then exponentially down to silence over `decay`.
static func _env(t: float, attack: float, peak: float, decay: float) -> float:
	if t < 0:
		return 0.0
	if t < attack:
		return 0.0001 * pow(peak / 0.0001, t / attack)
	if t < attack + decay:
		return peak * pow(0.0001 / peak, (t - attack) / decay)
	return 0.0


static func _osc(kind: String, phase: float) -> float:
	var p := fposmod(phase, 1.0)
	match kind:
		"square":
			return 1.0 if p < 0.5 else -1.0
		"sawtooth":
			return 2.0 * p - 1.0
		"triangle":
			return 1.0 - 4.0 * absf(p - 0.5)
	return sin(TAU * p)


## A biquad filter (the Audio EQ Cookbook, as Web Audio uses), whose
## frequency may move: `freq` is a Callable of time or a number.
class Biquad:
	var kind: String
	var q: float
	var rate: float
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func _init(k: String, f: float, qv: float, r: float) -> void:
		kind = k
		q = qv
		rate = r
		tune(f)

	func tune(f: float) -> void:
		var w := TAU * clampf(f, 10, rate * 0.49) / rate
		var alpha := sin(w) / (2 * q)
		var c := cos(w)
		var a0 := 1 + alpha
		match kind:
			"lowpass":
				b0 = (1 - c) / 2
				b1 = 1 - c
				b2 = (1 - c) / 2
			"highpass":
				b0 = (1 + c) / 2
				b1 = -(1 + c)
				b2 = (1 + c) / 2
			_: # bandpass, 0 dB at the centre
				b0 = alpha
				b1 = 0
				b2 = -alpha
		a1 = -2 * c
		a2 = 1 - alpha
		b0 /= a0
		b1 /= a0
		b2 /= a0
		a1 /= a0
		a2 /= a0

	func step(x: float) -> float:
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y


static func _buf(dur: float, rate := RATE) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * rate))
	return b


## frequency at time t of an exponential ramp from f0 to f1 over d
static func _expo(f0: float, f1: float, t: float, d: float) -> float:
	return f0 * pow(f1 / f0, clampf(t / d, 0, 1))


## An oscillator through an optional filter, under an envelope, added in.
## `freq` maps time to frequency.
static func _tone(out: PackedFloat32Array, start: float, dur: float, kind: String, freq: Callable, env: Array, filt: Biquad = null) -> void:
	var phase := 0.0
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), out.size() - i0)
	for i in n:
		var t := float(i) / RATE
		phase += freq.call(t) / RATE
		var s := _osc(kind, phase)
		if filt:
			s = filt.step(s)
		out[i0 + i] += s * _env(t, env[0], env[1], env[2])


## White noise through a filter (its frequency may move) under an envelope.
static func _noise(out: PackedFloat32Array, start: float, dur: float, filt: Biquad, env: Array, freq = null, rate := RATE) -> void:
	var i0 := int(start * rate)
	var n := mini(int(dur * rate), out.size() - i0)
	for i in n:
		var t := float(i) / rate
		if freq != null and i % 16 == 0:
			filt.tune(freq.call(t))
		out[i0 + i] += filt.step(randf() * 2 - 1) * _env(t, env[0], env[1], env[2])


func whoosh(dur: float, freq: float) -> void:
	_play("whoosh%s:%s:%d" % [dur, freq, _variant()], func():
		var b := _buf(dur + 0.05)
		_noise(b, 0, dur + 0.05, Biquad.new("bandpass", freq * 0.6, 1.2, RATE), [dur * 0.4, 0.18, dur * 0.6], func(t): return _expo(freq * 0.6, freq * 1.6, t, dur))
		return b)


func impact() -> void:
	thud(160, 0.18)
	_play("impact%d" % _variant(), func():
		var f := 1800 + randf() * 400
		var b := _buf(0.1)
		_tone(b, 0, 0.1, "square", func(_t): return f, [0.003, 0.05, 0.08], Biquad.new("highpass", 1200, 0.707, RATE))
		return b)


func thud(freq: float, dur: float) -> void:
	_play("thud%s:%s" % [freq, dur], func():
		var b := _buf(dur + 0.05)
		_tone(b, 0, dur + 0.05, "sine", func(t): return _expo(freq, freq * 0.4, t, dur), [0.005, 0.35, dur])
		_noise(b, 0, dur, Biquad.new("lowpass", 900, 0.707, RATE), [0.003, 0.25, dur * 0.6])
		return b)


func shield_break() -> void:
	thud(70, 0.6)
	whoosh(0.35, 300)
	_play("shieldBreak", func():
		var b := _buf(0.3)
		_noise(b, 0, 0.3, Biquad.new("bandpass", 2400, 1.0, RATE), [0.002, 0.2, 0.25])
		return b)


func growl(freq: float, dur: float) -> void:
	_play("growl%s:%s" % [freq, dur], func():
		var b := _buf(dur + 0.05)
		_tone(b, 0, dur + 0.05, "sawtooth", func(t): return _expo(freq * 1.3, freq * 0.8, t, dur), [dur * 0.3, 0.12, dur * 0.7], Biquad.new("lowpass", freq * 5, 0.707, RATE))
		return b)


func death(heavy: bool) -> void:
	growl(50 if heavy else 90, 1.2 if heavy else 0.8)
	thud(50 if heavy else 80, 0.5)


func chime(freqs: Array, gap: float) -> void:
	_play("chime%s:%s" % [str(freqs), gap], func():
		var b := _buf((freqs.size() - 1) * gap + 1.0)
		for i in freqs.size():
			var fr: float = freqs[i]
			_tone(b, i * gap, 1.0, "triangle", func(_t): return fr, [0.01, 0.07, 0.9])
		return b)


func coins() -> void:
	_play("coins%d" % _variant(), func():
		var b := _buf(0.32)
		for i in 3:
			var fr := 2200 + randf() * 900
			_tone(b, i * 0.06 + randf() * 0.02, 0.15, "square", func(_t): return fr, [0.002, 0.025, 0.12])
		return b)


## a distant, slightly detuned bell, rendered at full level and played
## at `level`
func bell(level := 0.06, base := 196.0, bus := "Effects") -> void:
	var make := func():
		var b := _buf(4.0)
		var ratios := [1.0, 2.01, 2.76, 5.4]
		for i in ratios.size():
			var fr: float = base * ratios[i]
			_tone(b, 0, 4.0, "sine", func(_t): return fr, [0.01, 0.25 / (i + 1), 3.5 / (i * 0.5 + 1)])
		return b
	_play("bell%d" % roundi(base), make, level * 4, bus)


func crow() -> void:
	var make := func():
		var caws := 2 + rng.randi() % 2
		var b := _buf(caws * 0.32 + 0.25)
		for i in caws:
			_noise(b, i * 0.32, 0.25, Biquad.new("bandpass", 1300, 6, RATE), [0.02, 0.05, 0.18], func(t): return lerpf(1300, 900, clampf(t / 0.18, 0, 1)))
		return b
	_play("crow%d" % _variant(), make, 1.0, "Ambience")


func creak() -> void:
	var make := func():
		var to := 110 + randf() * 60
		var b := _buf(1.0)
		_tone(b, 0, 1.0, "sawtooth", func(t): return lerpf(140, to, clampf(t / 0.8, 0, 1)), [0.3, 0.025, 0.6], Biquad.new("bandpass", 600, 8, RATE))
		return b
	_play("creak%d" % _variant(), make, 1.0, "Ambience")


## The wind: band-passed noise whose centre and loudness drift. Rendered as
## a 24 s loop, with the drifts (0.09 and 0.13 Hz in the browser) rounded to
## whole turns of the loop and the ends cross-faded so it never clicks.
func _wind() -> AudioStreamWAV:
	var dur := 24.0
	var fade := int(1.0 * AMB_RATE)
	var n := int(dur * AMB_RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var f := Biquad.new("bandpass", 420, 0.6, AMB_RATE)
	for i in raw.size():
		var t := float(i) / AMB_RATE
		if i % 16 == 0:
			f.tune(420 + 220 * sin(TAU * 2.0 / dur * t))
		raw[i] = f.step(randf() * 2 - 1) * (0.06 + 0.03 * sin(TAU * 3.0 / dur * t))
	for i in fade:
		var k := float(i) / fade
		raw[i] = raw[i] * k + raw[n + i] * (1 - k)
	raw.resize(n)
	return _wav(raw, AMB_RATE, true)


## a low sawtooth rumble, louder near an elite's ground (one second loop)
func _rumble() -> AudioStreamWAV:
	var b := _buf(1.0, AMB_RATE)
	var f := Biquad.new("lowpass", 90, 0.707, AMB_RATE)
	for pass_ in 2: # the second pass starts with the filter settled, so it loops cleanly
		for i in b.size():
			b[i] = f.step(_osc("sawtooth", 38.0 * i / AMB_RATE))
	return _wav(b, AMB_RATE, true)


func update(dt: float) -> void:
	if not started:
		return
	if not warm.is_empty():
		warming = true
		warm.pop_front().call()
		warming = false
	next_crow -= dt
	next_bell -= dt
	next_creak -= dt
	if next_crow <= 0:
		crow()
		next_crow = 14 + randf() * 20
	if next_bell <= 0:
		bell(0.035, 180 + (rng.randi() % VARIANTS) * 10, "Ambience")
		next_bell = 35 + randf() * 40
	if next_creak <= 0:
		creak()
		next_creak = 12 + randf() * 18
	# low rumble rises near the elite's ground
	var p: Vector3 = game.player.position
	var danger := 0.0
	for z in Layout.danger_zones:
		var d := U.hyp(p.x - z.position[0], p.z - z.position[1])
		danger = maxf(danger, (1 - d / z.radius) * (0.3 if game.world_state.is_defeated(z.enemy) else 1.0))
	var want := maxf(0, danger) * 0.12
	rumble_level += (want - rumble_level) * (1 - exp(-dt / 0.5))
	rumble.volume_db = linear_to_db(maxf(rumble_level, 0.00001))
