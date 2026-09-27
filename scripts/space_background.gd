class_name SpaceBackground
extends Node2D
## Multi-layer parallax: far nebula -> dim stars -> galaxies & distant planets ->
## mid stars -> near nebula wisps -> twinkling stars -> dust.
##
## The layers are Parallax2D children in scenes/background/space_background.tscn:
## edit scroll_scale (depth), the sprite's modulate (brightness) or move the
## decoration sprites around. Tiled layers are tagged with the "tiled" metadata;
## at runtime they are counter-scaled against camera zoom so distant layers keep
## their size, like real far-away objects.

## Tiled layers: {parallax, sprite, tex_size, pixel, scroll}
var _layers: Array[Dictionary] = []


func _ready() -> void:
	z_index = -100
	for c in get_children():
		var p := c as Parallax2D
		if p == null or not p.has_meta("tiled"):
			continue
		var s := p.get_child(0) as Sprite2D
		_layers.append({"p": p, "s": s, "size": s.texture.get_size(), "pixel": s.scale.x,
				"scroll": p.scroll_scale.x})


## Distant layers barely react to camera zoom (like real far-away objects):
## each tile is counter-scaled by 1/zoom, weighted by how far the layer is.
func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var z := cam.zoom.x
	for l in _layers:
		var k: float = lerpf(1.0 / z, 1.0, l.scroll)
		var px: float = l.pixel * k
		(l.s as Sprite2D).scale = Vector2(px, px)
		(l.p as Parallax2D).repeat_size = l.size * px
