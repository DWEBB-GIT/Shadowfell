extends RefCounted
## The Coast has independent saves and can import a Campaign character once.

const POSITION_SUFFIX := ".lantern_coast.position"
const JOURNEY_SUFFIX := ".lantern_coast.journey"
const POSITION_VERSION := 1
const SHARED_FIELDS := [
	"progression", "inventory", "bar", "skills", "skillLadder", "spells",
	"reputation", "renown", "titles", "cooking", "builds",
]


static func position_identity(character: Dictionary) -> String:
	var key := str(character.get("key", ""))
	var id := str(character.get("id", ""))
	if key.is_empty() or id.is_empty():
		return ""
	# Roster IDs and the legacy key can be reused after deletion.
	return "%s.%s.%d" % [key, id, int(character.get("createdAt", 0))]


static func journey_key(character: Dictionary) -> String:
	return position_identity(character) + JOURNEY_SUFFIX


static func read_position(character_key: String) -> Dictionary:
	if character_key.is_empty():
		return {}
	var text = Store.get_item(character_key + POSITION_SUFFIX)
	if not text is String or text.length() > 512:
		return {}
	var data = JSON.parse_string(text)
	if not data is Dictionary or data.get("version") != POSITION_VERSION:
		return {}
	return _position(data)


static func save_position(character_key: String, position: Vector3, facing: float) -> Dictionary:
	if character_key.is_empty() or not position.is_finite() or not is_finite(facing):
		return {"ok": false, "reason": "The Lantern Coast position could not be saved."}
	var key := character_key + POSITION_SUFFIX
	var text := JSON.stringify({
		"version": POSITION_VERSION,
		"x": snappedf(position.x, 0.001),
		"z": snappedf(position.z, 0.001),
		"facing": snappedf(wrapf(facing, -PI, PI), 0.001),
	})
	if not Store.set_item(key, text) or Store.get_item(key) != text:
		return {"ok": false, "reason": "The Lantern Coast position could not be saved. Storage may be full or disabled."}
	return {"ok": true}


## Call with a validated campaign save and the current survey spawn. The caller
## must check the saved coordinates against the active terrain before using them.
static func project_snapshot(data: Dictionary, spawn: Dictionary = {}, map_key := "") -> Dictionary:
	var snapshot := {}
	var original := data.duplicate(true)
	for field in SHARED_FIELDS:
		if original.has(field):
			snapshot[field] = original[field]
	var landing := _position(spawn)
	if landing.is_empty():
		var start: Dictionary = Layout.player_start
		landing = {
			"x": float(start.position[0]),
			"z": float(start.position[1]),
			"facing": deg_to_rad(float(start.get("facing", 180))),
		}
	var saved_player: Dictionary = original.player
	var saved_health := float(saved_player.get("health", 1.0))
	var max_health := maxf(1.0, float(saved_player.get("maxHealth", saved_health)))
	snapshot["version"] = SaveManager.SAVE_VERSION
	snapshot["map"] = SaveManager.MAP_VERSION
	snapshot["worldId"] = Terrain.chosen_map() if map_key.is_empty() else map_key
	snapshot["player"] = {
		"appearance": saved_player.get("appearance"),
		"position": {"x": landing.x, "z": landing.z},
		"facing": landing.facing,
		"dead": false,
		"health": max_health if saved_player.get("dead", false) else clampf(saved_health, 1.0, max_health),
		"maxHealth": max_health,
	}
	snapshot["world"] = {
		"defeated": [], "collected": [], "examined": [], "drops": {}, "ground": [],
	}
	snapshot["quests"] = {"accepted": [], "done": [], "tracked": []}
	return snapshot


static func _position(data: Dictionary) -> Dictionary:
	var result := {}
	for field in ["x", "z", "facing"]:
		var value = data.get(field)
		if not (value is float or value is int) or not is_finite(value):
			return {}
		result[field] = float(value)
	result["facing"] = wrapf(result.facing, -PI, PI)
	return result
