@tool
class_name AsteroidField
extends Node2D
## A cluster of meteors. Place it in a level, set the radius and how many rocks;
## the rocks are scattered inside the circle when the game starts (a new random
## layout every game). In the editor the field is drawn as a dashed circle.

@export var count := 10:
	set(v):
		count = v
		queue_redraw()
@export var radius := 260.0:
	set(v):
		radius = v
		queue_redraw()
## "random" picks one kind for the whole field: mostly rock/iron, sometimes ice, rarely crystal.
@export_enum("random", "rock", "iron", "ice", "crystal") var kind := "random":
	set(v):
		kind = v
		queue_redraw()
@export_range(0.0, 1.0) var large_share := 0.15
@export_range(0.0, 1.0) var medium_share := 0.35
@export var drift_speed := 18.0        ## the whole field slowly drifts in a random direction

const EDITOR_COLORS := {"random": Color(0.8, 0.8, 0.8), "rock": Color(0.8, 0.65, 0.5),
		"iron": Color(0.6, 0.7, 0.9), "ice": Color(0.6, 0.9, 1.0), "crystal": Color(0.8, 0.5, 1.0)}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_spawn.call_deferred()


func _spawn() -> void:
	var k := kind
	if k == "random":
		var roll := randf()
		k = "crystal" if roll > 0.88 else ("ice" if roll > 0.68 else ("iron" if roll > 0.42 else "rock"))
	var drift := Vector2.from_angle(randf() * TAU) * randf_range(0.0, drift_speed)
	var placed: Array[Vector3] = []
	for i in count:
		var size_class := 0
		var r := randf()
		if r < large_share:
			size_class = 2
		elif r < large_share + medium_share:
			size_class = 1
		var rad: float = Asteroid.TEX_SIZE[size_class] * 0.5 * Game.PIXEL
		for attempt in 20:
			var pos := global_position + Vector2.from_angle(randf() * TAU) * sqrt(randf()) * radius
			var ok := true
			for q in placed:
				if pos.distance_to(Vector2(q.x, q.y)) < rad + q.z + 6.0:
					ok = false
					break
			if ok:
				placed.append(Vector3(pos.x, pos.y, rad))
				var vel := drift + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 10.0)
				Game.world.add_child(Asteroid.create(k, size_class, pos, vel))
				break


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var col: Color = EDITOR_COLORS.get(kind, Color.WHITE)
	var segs := 48
	for i in segs:
		if i % 2 == 0:
			var a0 := TAU * i / segs
			draw_arc(Vector2.ZERO, radius, a0, a0 + TAU / segs, 3, col, 3.0)
	# A few dots hinting at density.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in count:
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius
		draw_circle(p, 8.0, Color(col, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(-40, -radius - 12), "%s x%d" % [kind, count],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)
