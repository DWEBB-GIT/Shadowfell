class_name AudioSystem
extends Node
## Every sound, synthesised (src/systems/audio.js): there are no audio files
## to ship. The browser build plays a Web Audio graph per sound; here each
## sound is rendered once into a sample buffer by the same recipe
## (oscillators, noise, filters, the same envelopes) and then replayed.
## Sounds with a random part keep a few rendered variants.
## Three buses, as the Settings sliders: master, effects and ambience.
## Dan's recorded sounds (assets/sounds) replace the synth where one fits;
## a name in SFX with several files picks one at random each time.

const RATE := 22050 ## effects
const AMB_RATE := 11025 ## the rumble loop (nothing high in them)
const VOICES := 16
const VARIANTS := 4
const SFX_DIR := "res://assets/sounds/"
const SFX := {
	"swing": ["sword_swing_1.wav", "sword_swing_2.wav", "sword_swing_3.wav"],
	"hit": ["sword_hit_1.wav", "sword_hit_2.wav", "sword_hit_3.wav"],
	"parry": ["parry_1.wav", "parry_2.wav", "parry_3.wav"],
	"shot": ["bow_shot_1.wav", "bow_shot_2.wav"],
	"block": ["shield_block.mp3"],
	"lunge": ["heavy_whoosh.mp3"],
	"wolf": ["wolf_growl.mp3"],
	"gold": ["gold.ogg"],
	"pickup": ["pickup.ogg"],
	"pickup_weapon": ["pickup_weapon.ogg"],
	"pickup_potion": ["pickup_potion.mp3"],
	"harvest": ["harvest.mp3"],
	"equip": ["equip_1.ogg", "equip_2.ogg"],
	"equip_weapon": ["equip_weapon.mp3"],
	"equip_armour": ["equip_armour.ogg"],
	"level_up": ["level_up.mp3"],
	"quest_complete": ["quest_complete.mp3"],
	"quest_log": ["quest_log.mp3"],
	"panel": ["panel_open.mp3"],
	"potion": ["potion_drink.mp3"],
	"chest": ["chest_open_1.wav", "chest_open_2.wav"],
	"buy": ["buy.ogg"],
	"click": ["ui_click.wav"],
	"mine": ["mine_1.wav", "mine_2.wav", "mine_3.wav", "mine_4.wav", "mine_5.wav"],
	"skin": ["skin.mp3"],
	"shrine": ["shrine.wav"],
	"campfire": ["campfire.mp3"],
	"fish_cast": ["fishing_cast.mp3"],
	"fish_out": ["fishing_out.mp3"],
	"step_dirt": ["step_dirt_1.wav", "step_dirt_2.wav", "step_dirt_3.wav", "step_dirt_4.wav", "step_dirt_5.wav"],
	"step_stone": ["step_stone_1.wav", "step_stone_2.wav", "step_stone_3.wav", "step_stone_4.wav", "step_stone_5.wav"],
	"step_wood": ["step_wood_1.wav", "step_wood_2.wav", "step_wood_3.wav", "step_wood_4.wav"],
}
## region id -> ambience loop (anywhere else keeps the forest)
const AMB_LOOPS := {"brackenford": "amb_town.mp3", "fallen_road": "amb_forest.mp3", "blackwood": "amb_forest.mp3"}
const MUSIC := "music_loop.ogg" ## Dan's background track, looped under everything
const STEP_GAP := 0.42 ## seconds between footsteps at a walk
const GROWL := {"brute": [70, 0.5], "hound": [170, 0.25], "archer": [220, 0.2], "seer": [95, 0.45]}

var game
var started := false
var cache := {} ## recipe key -> AudioStreamWAV
var voices: Array = [] ## AudioStreamPlayer pool
var next_voice := 0
var click_player: AudioStreamPlayer
var rumble: AudioStreamPlayer
var rumble_level := 0.0
var next_crow := 6.0
var next_bell := 18.0
var next_creak := 10.0
var rng := RandomNumberGenerator.new()
var warm: Array = [] ## sounds still to render ahead of need, one per frame
var warming := false
var _force_variant := -1
var sfx_cache := {} ## file -> AudioStream
var amb_loop: AudioStreamPlayer
var amb_file := ""
var music: AudioStreamPlayer
var step_t := 0.0


## Every sound the game can play is made ahead, a little each frame from
## the title screen on, so no fight or chime stalls a frame to make one.
func _ready() -> void:
	warm = [func(): bell(1, 880), func(): bell(1, 440), func(): bell(1, 660), func(): bell(1, 660),
		func(): chime([392, 523, 659], 0.25), func(): chime([392, 494, 587, 784], 0.22),
		func(): chime([660, 990], 0.12), func(): chime([330, 415], 0.15), func(): shield_break(),
		func(): whoosh(0.3, 700), func(): whoosh(0.35, 300), func(): death(true), func(): death(false),
		func(): growl(55, 1.4), func(): growl(120, 0.35)]
	for t in [[160, 0.18], [110, 0.25], [90, 0.3], [180, 0.12], [70, 0.6], [60, 0.6], [220, 0.12]]:
		warm.append(func(): thud(t[0], t[1]))
	for g in GROWL.values():
		warm.append(func(): growl(g[0], g[1]))
	for v in VARIANTS:
		warm.append(func(): bell(1, 180 + v * 10, "Ambience"))
		for f in [func(): whoosh(0.18, 900), func(): impact(), func(): coins(), func(): crow(), func(): creak()]:
			warm.append(func():
				_force_variant = v
				f.call()
				_force_variant = -1)


## a few milliseconds of sound-making per frame until all are made
func _process(_dt: float) -> void:
	if warm.is_empty():
		set_process(false)
		return
	warm_some(4000)


## makes sounds from the warm list for about `budget` microseconds (the
## loading screen gives it more)
func warm_some(budget: int) -> void:
	var until := Time.get_ticks_usec() + budget
	warming = true
	while not warm.is_empty() and Time.get_ticks_usec() < until:
		warm.pop_front().call()
	warming = false


func _init(g) -> void:
	game = g
	name = "Audio"


## Starts the buses, the ambient loops and the event hooks. A web export
## unlocks sound on the first click or key, as the browser build does.
func start() -> void:
	if started:
		return
	started = true
	for bus in ["Effects", "Ambience", "Music"]:
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
	rumble = _loop(_rumble(), "Ambience")
	rumble.volume_db = -80.0
	amb_loop = AudioStreamPlayer.new()
	amb_loop.bus = "Ambience"
	amb_loop.volume_db = -8.0
	add_child(amb_loop)
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	music.volume_db = -10.0
	add_child(music)
	var m = _stream(MUSIC)
	if m != null:
		m = m.duplicate()
		m.loop = true
		music.stream = m
		music.play()
	game.events.on("regionChanged", func(e): _ambience(str(e.region.get("id", ""))))
	if game.get("region") != null:
		_ambience(str(game.region.get("id", "")))
	_bind()


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
	for b in [["Master", "volMaster"], ["Effects", "volEffects"], ["Ambience", "volAmbience"], ["Music", "volMusic"]]:
		var v: float = pow(float(st.get_value(b[1])) / 100.0, 2)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(b[0]), linear_to_db(maxf(v, 0.00001)))
	if game.hud:
		game.hud.set_muted(float(st.get_value("volMaster")) == 0)


func _bind() -> void:
	var ev = game.events
	ev.on("playerSwing", func(_e): sfx("swing", 0.7))
	ev.on("playerShot", func(_e): sfx("shot", 0.7))
	ev.on("fishCast", func(_e): sfx("fish_cast", 0.8))
	ev.on("fishReel", func(_e): sfx("fish_out", 0.8))
	ev.on("enemyHit", func(e):
		if e.get("kind") != "strike":
			return
		sfx("hit")
		if e.get("crit"):
			thud(90, 0.3)) # a crit lands with a deeper crunch
	ev.on("burst", func(_e): shield_break())
	ev.on("playerBrace", func(_e): thud(180, 0.12))
	ev.on("braceBlock", func(_e):
		sfx("block"))
	ev.on("enemyWhiff", func(_e): sfx("parry", 0.6))
	ev.on("corpseLooted", func(_e): sfx("gold"))
	ev.on("enemyWindup", func(e):
		if e.enemy.type == "hound":
			sfx("wolf", 0.6)
			return
		var g: Array = GROWL.get(e.enemy.type, [120, 0.35])
		growl(g[0], g[1]))
	ev.on("playerHurt", func(_e): thud(110, 0.25))
	ev.on("enemyDefeated", func(e): death(e.enemy.type == "brute"))
	ev.on("lootCollected", func(e):
		var def: Dictionary = Items.get_def(str(e.get("item", ""))) if e.get("item") else {}
		if e.get("node"):
			sfx("harvest", 0.8) # a gathering node, picked
		elif def.get("kind") == "weapon":
			sfx("pickup_weapon")
		elif str(def.get("id", "")).ends_with("draught"):
			sfx("pickup_potion")
		else:
			sfx("pickup"))
	ev.on("coins", func(_e): sfx("gold"))
	ev.on("levelUp", func(_e): sfx("level_up"))
	ev.on("shrineRest", func(_e): sfx("shrine", 0.6))
	ev.on("draught", func(_e): sfx("potion"))
	ev.on("itemEquipped", func(e):
		var kind := str(Items.get_def(str(e.id)).get("kind", ""))
		if kind == "weapon" or kind == "shield":
			sfx("equip_weapon", 0.7)
		elif kind == "armor":
			sfx("equip_armour", 0.7)
		else:
			sfx("equip", 0.7))
	ev.on("chestOpened", func(_e): sfx("chest"))
	ev.on("itemBought", func(_e): sfx("buy"))
	ev.on("itemSold", func(_e): sfx("gold"))
	ev.on("mined", func(_e): sfx("mine"))
	ev.on("skinned", func(_e): sfx("skin"))
	ev.on("campPitched", func(_e): sfx("campfire", 0.6))
	ev.on("playerDied", func(_e): growl(55, 1.4))
	ev.on("playerLunge", func(_e): sfx("lunge"))
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
	ev.on("questComplete", func(_e): sfx("quest_complete", 0.8))


# ------------------------------------------------------------- playback
## Plays one of Dan's recorded sounds by its SFX name.
func sfx(id: String, level := 1.0) -> void:
	if not started or level <= 0 or not SFX.has(id):
		return
	var files: Array = SFX[id]
	var s = _stream(files[rng.randi() % files.size()])
	if s == null:
		return
	var p: AudioStreamPlayer = voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	p.stream = s
	p.bus = "Effects"
	p.volume_db = linear_to_db(level)
	p.play()


## Every button's click (game.gd hooks each one as it enters the tree). It
## has its own player, so the title screen clicks before the buses start.
func click() -> void:
	if click_player == null:
		click_player = AudioStreamPlayer.new()
		click_player.stream = _stream(SFX.click[0])
		click_player.volume_db = linear_to_db(0.55)
		add_child(click_player)
	click_player.bus = "Effects" if started else "Master"
	click_player.play()


func _stream(file: String) -> AudioStream:
	if not sfx_cache.has(file):
		sfx_cache[file] = load(SFX_DIR + file)
	return sfx_cache[file]


## the region's ambience loop; the same file carries on across a border
func _ambience(region_id: String) -> void:
	var file: String = AMB_LOOPS.get(region_id, "amb_forest.mp3")
	if file == amb_file:
		return
	amb_file = file
	var s = _stream(file)
	if s == null:
		return
	s = s.duplicate()
	s.loop = true
	amb_loop.stream = s
	amb_loop.play()


## footsteps while the player moves: wood indoors, stone in town, dirt elsewhere
func _footsteps(dt: float) -> void:
	var pl = game.player
	if pl == null or not pl.moving:
		step_t = 0.0
		return
	step_t -= dt
	if step_t > 0:
		return
	step_t = STEP_GAP
	var surface := "step_dirt"
	if game.world.indoors != null:
		surface = "step_wood"
	elif amb_file == "amb_town.mp3":
		surface = "step_stone"
	sfx(surface, 0.35)


## Plays a rendered sound (made the first time it is asked for) at a level.
func _play(key: String, make: Callable, level := 1.0, bus := "Effects") -> void:
	if not warming and (not started or level <= 0):
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
	return _force_variant if _force_variant >= 0 else rng.randi() % VARIANTS


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
	_footsteps(dt)
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
