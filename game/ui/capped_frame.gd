class_name CappedFrame
extends StyleBox
## A bronze nine-patch frame with an end cap on each side, as on the UI
## kit's action bar. The caps sit in `cap_room` at each end of the box, so
## the layout makes space for them.

var inner: StyleBoxTexture
var left: Texture2D
var right: Texture2D
var cap_scale := 1.1 ## cap height against the frame's height
var cap_room := 22.0 ## the room each cap takes beside the frame
var overlap := 7.0 ## how far each cap tucks over the frame


func _draw(ci: RID, rect: Rect2) -> void:
	var body := rect.grow_individual(-cap_room, 0, -cap_room, 0)
	inner.draw(ci, body)
	var h := rect.size.y * cap_scale
	var y := rect.get_center().y - h / 2
	var lw := left.get_width() * h / left.get_height()
	var rw := right.get_width() * h / right.get_height()
	# each cap reaches from the box's edge and tucks over the frame
	RenderingServer.canvas_item_add_texture_rect(ci, Rect2(body.position.x + overlap - lw, y, lw, h), left.get_rid())
	RenderingServer.canvas_item_add_texture_rect(ci, Rect2(body.end.x - overlap, y, rw, h), right.get_rid())
