extends SceneTree
func _initialize() -> void:
	var bow=load("res://game/render/held_bow.gd").new()
	bow.name="HuntingBow"
	bow.build()
	var queue:Array=bow.get_children()
	while not queue.is_empty():
		var node:Node=queue.pop_back()
		node.owner=bow
		queue.append_array(node.get_children())
	var packed:=PackedScene.new()
	var result:=packed.pack(bow)
	if result==OK:result=ResourceSaver.save(packed,"res://assets/models/weapons/hunting_bow.tscn")
	bow.free()
	print("bow_asset_build: ",result)
	quit(0 if result==OK else 1)
