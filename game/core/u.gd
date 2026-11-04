@tool
class_name U
extends RefCounted
## Small helpers the ported systems share, so GDScript behaves like the
## browser build where the two languages differ (rounding, number text).


## JavaScript's Math.round: halves go up (-2.5 -> -2), unlike round().
static func jround(x: float) -> int:
	return int(floor(x + 0.5))


static func hyp(x: float, z: float) -> float:
	return sqrt(x * x + z * z)


## A number as the browser prints it: 12, not 12.0; 1.5 stays 1.5.
static func n(v) -> String:
	if typeof(v) == TYPE_FLOAT and is_equal_approx(v, round(v)):
		return str(int(round(v)))
	return str(v)


## a length of time for a tooltip: "45 sec", "1 minute", "2 minutes 30 seconds"
static func span(sec: float) -> String:
	if sec < 60:
		return "%s sec" % n(sec)
	var m := floori(sec / 60.0)
	var s := roundi(sec - m * 60)
	var out := "%d minute%s" % [m, "" if m == 1 else "s"]
	if s > 0:
		out += " %d second%s" % [s, "" if s == 1 else "s"]
	return out


## "1 gold 20 silver", "35 silver": the purse holds silver, 100 to the gold.
static func money(amount) -> String:
	var a := maxi(0, int(amount))
	var gold := a / 100
	var silver := a % 100
	var parts := []
	if gold:
		parts.append("%d gold" % gold)
	if silver or not gold:
		parts.append("%d silver" % silver)
	return " ".join(parts)


## Coins in the data are whole silver, or a range {min, max} rolled when
## handed over (money.js coinRange).
static func coin_range(c) -> Array:
	if c is Dictionary:
		var lo := int(c.get("min", 0))
		return [lo, int(c.get("max", lo))]
	return [int(c) if c else 0, int(c) if c else 0]


static func roll_coins(c, rand: Callable) -> int:
	var r := coin_range(c)
	return r[0] + int(floor(rand.call() * (r[1] - r[0] + 1))) if r[1] > r[0] else r[0]


## "a" or "an" before a word.
static func article(word: String) -> String:
	return "an" if word.length() > 0 and "aeiouAEIOU".contains(word[0]) else "a"


## JavaScript's `x.toFixed(digits)`.
static func fixed(v: float, digits: int) -> String:
	return ("%." + str(digits) + "f") % v


## A shallow copy of a dictionary with some keys replaced: { ...d, ...over }.
static func merged(d: Dictionary, over: Dictionary) -> Dictionary:
	var out := d.duplicate()
	for k in over:
		out[k] = over[k]
	return out


## Turn towards `target` by at most `max_step` radians (shortest way round).
static func turn_towards(current: float, target: float, max_step: float) -> float:
	var diff := target - current
	while diff > PI:
		diff -= TAU
	while diff < -PI:
		diff += TAU
	if absf(diff) <= max_step:
		return target
	return current + signf(diff) * max_step


## The seeded random of src/world/terrain.js (mulberry32), so the woodland is
## planted exactly where the browser build plants it. Call next() for [0, 1).
class Seeded:
	var s: int

	func _init(seed: int) -> void:
		s = seed & 0xFFFFFFFF

	func next() -> float:
		s = (s + 0x6D2B79F5) & 0xFFFFFFFF
		var t := s
		t = _imul(t ^ (t >> 15), t | 1)
		t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

	static func _imul(a: int, b: int) -> int:
		return (a * b) & 0xFFFFFFFF
