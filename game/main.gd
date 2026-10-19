extends Node3D
## The game scene: the world, the player and the camera. Each frame it names
## the region the player is in and thickens the fog under the Blackwood pines.

@onready var player: Node3D = $Player
@onready var env: Environment = $WorldEnvironment.environment
@onready var sun: DirectionalLight3D = $Sun
@onready var region_label: Label = $HUD/Region

var _regions: Array


func _ready() -> void:
	_regions = GameData.section("world", "regions")


func _process(_delta: float) -> void:
	var z := player.position.z
	for r in _regions:
		if r.minZ == null or z >= r.minZ:
			region_label.text = r.name
			break
	var k := Terrain.blackwoodness(z)
	env.fog_light_color = Color("3a4244").lerp(Color("1d2725"), k)
	env.background_color = env.fog_light_color
	env.fog_depth_begin = lerpf(14.0, 9.0, k)
	env.fog_depth_end = lerpf(40.0, 32.0, k)
	sun.light_energy = lerpf(1.6, 1.6 * 0.68, k)
