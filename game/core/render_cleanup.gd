class_name RenderCleanup
extends RefCounted
## Detach renderer instances before their privately owned materials disappear.
static func detach(root: Node) -> void:
	for child in root.get_children():
		detach(child)
	if root is MeshInstance3D:
		root.mesh = null
		root.material_override = null
	elif root is GPUParticles3D:
		root.emitting = false
	elif root is CPUParticles3D:
		root.emitting = false
	elif root is TextureRect:
		root.texture = null
	elif root is SubViewport:
		root.render_target_update_mode = SubViewport.UPDATE_DISABLED
