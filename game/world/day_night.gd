class_name DayNight
extends RefCounted
## The light of the hour (foundations step 3, Dan 2026-11-04). The world
## clock (WorldState.hour) moves the sun from the east at dawn (6) through
## the south to the west at dusk (18); between, a dim blue moon crosses the
## sky. Game multiplies its grade (Game.air plus colour zones) by this, so
## the Blackwood gloom and every colour zone keep their own look at any hour.
## At about four in the afternoon it is the look Dan approved in PR #108:
## the low amber sun from the west-southwest. Pure maths: a server could ask
## the same of any hour.

const DISTANCE := 29.0 ## how far the light sits from what it lights
const SUN_LOW := Color("ff9a55") ## at the horizon
const SUN_AFTERNOON := Color("ffe0b2") ## the PR #108 sun
const SUN_NOON := Color("fff0d8")
const MOON := Color("9fb4e0")
const NIGHT_AIR := Color(0.62, 0.70, 1.0) ## fill light, multiplied, at night
const NIGHT_FOG := Color(0.26, 0.30, 0.44) ## haze and background, multiplied
const DUSK_FOG := Color(1.0, 0.72, 0.56) ## the haze warms as the sun goes


## sun (and moon) height: 1 at noon, 0 at 6 and 18, -1 at midnight
static func height(hour: float) -> float:
	return sin(PI * (hour - 6.0) / 12.0)


## The light at `hour`:
## - offset: from what is lit to the light (sun by day, moon by night)
## - colour, light: the light's colour and its share of the full sun
## - ambient, ambientTint: the fill light's share and its colour multiplier
## - fogTint: multiplies the haze and background colour
## - daylight: 0 at night, 1 in full day
static func light(hour: float) -> Dictionary:
	var cfg: Dictionary = DB.CONFIG.clock
	var d := height(hour)
	var sun_k := smoothstep(-0.08, 0.3, d)
	var moon_k := smoothstep(-0.05, 0.3, -d)
	var sun_light := sun_k * (0.85 + 0.3 * maxf(d, 0.0))
	var moon_light := moon_k * float(cfg.moonlight)
	var out := {"daylight": sun_k}
	if sun_light >= moon_light:
		# east (+x) at dawn, south (+z) at noon, west (-x) at dusk
		var az := PI * (hour - 6.0) / 12.0
		var elev := deg_to_rad(12.0 + 46.0 * maxf(d, 0.0))
		out.offset = _offset(Vector2(cos(az), sin(az) * 0.7), elev)
		var c := SUN_LOW.lerp(SUN_AFTERNOON, smoothstep(0.05, 0.5, d))
		out.colour = c.lerp(SUN_NOON, smoothstep(0.5, 1.0, d))
		out.light = sun_light
	else:
		var night := fposmod(hour - 18.0, 24.0)
		var az := PI * night / 12.0
		out.offset = _offset(Vector2(cos(az), sin(az) * 0.7), deg_to_rad(22.0 + 30.0 * maxf(-d, 0.0)))
		out.colour = MOON
		out.light = moon_light
	out.ambient = lerpf(float(cfg.nightAmbient), 1.0, sun_k)
	out.ambientTint = NIGHT_AIR.lerp(Color.WHITE, sun_k)
	# a warm haze while the sun is near the horizon, either side of it
	var twilight := clampf(1.0 - absf(d) / 0.22, 0.0, 1.0) * 0.45
	out.fogTint = NIGHT_FOG.lerp(Color.WHITE, sun_k).lerp(DUSK_FOG * maxf(sun_k, 0.5), twilight)
	return out


static func _offset(dir: Vector2, elev: float) -> Vector3:
	var h := dir.normalized() * DISTANCE * cos(elev)
	return Vector3(h.x, DISTANCE * sin(elev), h.y)


## "14:05"
static func clock_text(hour: float) -> String:
	var m := int(floor(fposmod(hour, 24.0) * 60.0))
	return "%02d:%02d" % [m / 60, m % 60]


## a word for the time of day
static func part_of_day(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	if h < 5.0:
		return "Night"
	if h < 7.0:
		return "Dawn"
	if h < 12.0:
		return "Morning"
	if h < 17.0:
		return "Afternoon"
	if h < 19.5:
		return "Evening"
	if h < 21.0:
		return "Dusk"
	return "Night"
