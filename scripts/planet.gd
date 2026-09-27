@tool
class_name Planet
extends StaticBody2D
## Deformable planet we defend. Enemy hits carve craters into its pixel image,
## the collision polygons are rebuilt from the new alpha mask, small detached
## islands break off as meteors. When its integrity (hp) runs out it shatters,
## taking its defense post and turrets with it, and disappears from the map.
##
## Scene layout (scenes/world/planet.tscn): Atmosphere (Sprite2D), Sprite (Sprite2D).
## This is a @tool script only so that changing `kind` in the Inspector swaps the
## picture in the editor; all game logic runs in the game only.

signal lost(planet: Planet)

const ATMO_PAD := 18               ## atmosphere glow reach, texture px
const DETACH_AREA := 500.0        ## islands smaller than this (in texture px^2) break off
const DEATH_FRACTION := 0.35      ## shatter when less than this much mass is left
const REBUILD_INTERVAL := 0.15
const PIXEL := 2.0                ## == PIXEL (kept local so the editor preview works)
const KIND_DATA := {
	"terra": {"rock": "rock", "debris": Color("3f7d33"), "map": Color("3b82c4"), "atmo": Color("6ab8ff"), "hot": false},
	"lava": {"rock": "iron", "debris": Color("ff7a2a"), "map": Color("ff6a30"), "atmo": Color("ff6a30"), "hot": true},
	"ice": {"rock": "ice", "debris": Color("bfe3f3"), "map": Color("bfe3f3"), "atmo": Color("9ff0ff"), "hot": false},
	"toxic": {"rock": "crystal", "debris": Color("c46bb5"), "map": Color("b06ac8"), "atmo": Color("b6ff7a"), "hot": false},
	"mars": {"rock": "rock", "debris": Color("d27a45"), "map": Color("d27a45"), "atmo": Color("ffb48a"), "hot": false},
}

## Look and loot of the planet: Терра, Вулкан, Криос, Токсис, Марс.
@export_enum("terra", "lava", "ice", "toxic", "mars") var kind := "terra":
	set(v):
		kind = v
		_update_preview()
@export var max_hp := 1000.0           ## integrity before it explodes
@export var is_home := false           ## losing the home planet ends the game

var image: Image
var texture: ImageTexture
var radius := 200.0
var map_color := Color.WHITE
var mass_fraction := 1.0
var hp := 1000.0
var alive := true
## 0 = calm, 1 = a wave is heading here, 2 = enemies are at the planet.
var threat := 0
var post: DefensePost
var turrets: Array[Turret] = []

var _size := Vector2i.ZERO
var _half := Vector2.ZERO
var _initial_pixels := 1
var _pixels := 1
var _dirty := false
var _rebuild_cd := 0.0
var _shapes: Array[Node] = []
var _sprite: Sprite2D
var _atmo: Sprite2D
var _dead := false
var _data: Dictionary
var _samples := PackedVector2Array()   ## local points on the remaining mass (aim candidates)


## Editor: show the chosen planet picture.
func _update_preview() -> void:
	var spr := get_node_or_null("Sprite") as Sprite2D
	if spr:
		spr.texture = load("res://assets/sprites/planet_%s.png" % kind)


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_preview()
		return
	add_to_group(&"planets")
	z_index = -2
	hp = max_hp
	_data = KIND_DATA[kind]
	map_color = _data.map
	collision_layer = Game.L_PLANETS
	collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.3
	mat.friction = 0.4
	physics_material_override = mat

	var src: Texture2D = load("res://assets/sprites/planet_%s.png" % kind)
	image = src.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	_size = image.get_size()
	_half = Vector2(_size) * 0.5
	texture = ImageTexture.create_from_image(image)
	radius = _size.x * 0.5 * PIXEL

	_sprite = _child_sprite("Sprite")
	_sprite.texture = texture
	# Atmosphere: a padded quad whose shader glows around the *current* planet mask,
	# so the halo follows the deformation.
	var quad := Image.create(_size.x + ATMO_PAD * 2, _size.y + ATMO_PAD * 2, false, Image.FORMAT_RGBA8)
	quad.fill(Color.WHITE)
	var atmo_mat := ShaderMaterial.new()
	atmo_mat.shader = preload("res://shaders/planet_atmo.gdshader")
	atmo_mat.set_shader_parameter("planet_tex", texture)
	atmo_mat.set_shader_parameter("planet_size", Vector2(_size))
	atmo_mat.set_shader_parameter("pad", float(ATMO_PAD))
	atmo_mat.set_shader_parameter("glow_color", _data.atmo)
	_atmo = _child_sprite("Atmosphere")
	_atmo.texture = ImageTexture.create_from_image(quad)
	_atmo.material = atmo_mat

	var bm := BitMap.new()
	bm.create_from_image_alpha(image, 0.5)
	_initial_pixels = max(bm.get_true_bit_count(), 1)
	_pixels = _initial_pixels
	_rebuild_collision()
	Game.planets.append(self)


func _child_sprite(node_name: String) -> Sprite2D:
	var spr := get_node_or_null(node_name) as Sprite2D
	if spr == null:
		spr = Sprite2D.new()
		spr.name = node_name
		add_child(spr)
	spr.scale = Vector2(PIXEL, PIXEL)
	return spr


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	Game.planets.erase(self)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _dead:
		return
	_rebuild_cd -= delta
	if _dirty and _rebuild_cd <= 0.0 and not _dead:
		_dirty = false
		_rebuild_cd = REBUILD_INTERVAL
		_rebuild_collision()
	_atmo.modulate.a = lerp(_atmo.modulate.a, 0.4 + 0.6 * mass_fraction, 1.0 - exp(-3.0 * delta))


## Integrity shown on the map: the worse of remaining hp and remaining mass
## (mass counts down to the shatter threshold, so 0 = about to explode).
func hp_fraction() -> float:
	var by_mass := (mass_fraction - DEATH_FRACTION) / (1.0 - DEATH_FRACTION)
	return clamp(min(hp / max_hp, by_mass), 0.0, 1.0)


## Called by enemy projectiles (allied fire never damages planets).
func take_hit(point: Vector2, dir: Vector2, dmg: float, heavy: bool) -> void:
	if _dead:
		return
	hp -= dmg
	var r: float = 15.0 if heavy else clamp(3.0 + dmg * 0.15, 3.5, 9.0)
	var local := to_local(point) / PIXEL + _half
	local += dir.rotated(-global_rotation) * r * 0.3
	var removed := carve(local, r)
	if removed.x > 0:
		var count := int(clamp(removed.x / 5.0, 3.0, 40.0))
		Game.debris(point, Color(removed.y, removed.z, removed.w), count, 90.0 + r * 12.0)
		Game.play_sound("crunch", point, 0.0 if heavy else -8.0)
		if heavy:
			Game.shake(3.0)
	if hp <= 0.0:
		_shatter()


## Removes a disc of pixels (texture space). Returns Vector4(count, avg r, g, b).
func carve(center: Vector2, r: float) -> Vector4:
	var ro := r + 2.5
	var r2 := r * r
	var ro2 := ro * ro
	var x0 := maxi(0, floori(center.x - ro))
	var x1 := mini(_size.x - 1, ceili(center.x + ro))
	var y0 := maxi(0, floori(center.y - ro))
	var y1 := mini(_size.y - 1, ceili(center.y + ro))
	var removed := 0
	var sum := Color(0, 0, 0, 0)
	var hot: bool = _data.hot
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := x + 0.5 - center.x
			var dy := y + 0.5 - center.y
			var d2 := dx * dx + dy * dy
			if d2 > ro2:
				continue
			var px := image.get_pixel(x, y)
			if px.a < 0.5:
				continue
			# Jagged crater edge.
			if d2 < r2 - randf() * r * 1.6:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				removed += 1
				sum += px
			else:
				image.set_pixel(x, y, _scorch(px, hot))
	if removed > 0:
		_pixels -= removed
		mass_fraction = float(_pixels) / _initial_pixels
		texture.update(image)
		_dirty = true
		sum /= removed
	return Vector4(removed, sum.r, sum.g, sum.b)


func _scorch(px: Color, hot: bool) -> Color:
	if px.v < 0.12:
		return px
	var roll := randf()
	if roll < (0.35 if hot else 0.12):
		return Color("ff8a2a") if roll < 0.06 else Color("c0401c")
	return px.lerp(Color(0.12, 0.07, 0.09), 0.45)


func _rebuild_collision() -> void:
	for s in _shapes:
		remove_child(s)
		s.queue_free()
	_shapes.clear()

	var bm := BitMap.new()
	bm.create_from_image_alpha(image, 0.5)
	var polys := bm.opaque_to_polygons(Rect2i(Vector2i.ZERO, _size), 1.2)
	var areas: Array[float] = []
	var biggest := 0.0
	for poly in polys:
		var a := absf(_polygon_area(poly))
		areas.append(a)
		biggest = maxf(biggest, a)

	var detached := false
	for i in polys.size():
		var poly: PackedVector2Array = polys[i]
		if areas[i] < 3.0:
			continue
		if areas[i] < DETACH_AREA and areas[i] < biggest * 0.5:
			_break_off(poly, areas[i])
			detached = true
			continue
		var pts := PackedVector2Array()
		pts.resize(poly.size())
		for j in poly.size():
			pts[j] = (poly[j] - _half) * PIXEL
		# Self-intersecting outlines (rare after heavy carving) can't be split into convex
		# pieces and the engine would log an error - check with a quiet triangulation first.
		var parts: Array[PackedVector2Array] = []
		if not Geometry2D.triangulate_polygon(pts).is_empty():
			parts = Geometry2D.decompose_polygon_in_convex(pts)
		if parts.is_empty():
			var cp := CollisionPolygon2D.new()
			cp.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
			cp.polygon = pts
			add_child(cp)
			_shapes.append(cp)
			continue
		for part in parts:
			var cs := CollisionShape2D.new()
			var shape := ConvexPolygonShape2D.new()
			shape.points = part
			cs.shape = shape
			add_child(cs)
			_shapes.append(cs)
	if detached:
		texture.update(image)
	_refresh_samples()
	if mass_fraction < DEATH_FRACTION:
		_shatter()


## Random points on what is left of the planet, used by attackers to aim.
func _refresh_samples() -> void:
	_samples.clear()
	for i in 700:
		var p := Vector2i(randi() % _size.x, randi() % _size.y)
		if image.get_pixelv(p).a > 0.5:
			_samples.append((Vector2(p) + Vector2(0.5, 0.5) - _half) * PIXEL)
			if _samples.size() >= 64:
				break


## Where a shooter at `from` should aim to actually hit this planet.
## The centre works while the planet is whole; once a tunnel is drilled through,
## shots at the centre fly out the other side, so we pick a point on the remaining
## mass that a straight shot from `from` really reaches.
func aim_point(from: Vector2) -> Vector2:
	var space := get_world_2d().direct_space_state
	if _ray_hits_me(space, from, global_position):
		return global_position
	var candidates := Array(_samples)
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return from.distance_squared_to(to_global(a)) < from.distance_squared_to(to_global(b)))
	for i in mini(8, candidates.size()):
		var g := to_global(candidates[i])
		if _ray_hits_me(space, from, g):
			return g
	return to_global(candidates[0]) if not candidates.is_empty() else global_position


func _ray_hits_me(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	# Extend a little past the point so a ray ending right at the surface still registers.
	var end := to + (to - from).normalized() * 8.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(from, end, Game.L_PLANETS))
	return not hit.is_empty() and hit.collider == self


## Erases a small detached island from the image and turns it into flying rocks.
func _break_off(poly: PackedVector2Array, area: float) -> void:
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	var removed := 0
	for y in range(maxi(0, int(rect.position.y) - 1), mini(_size.y, int(rect.end.y) + 2)):
		for x in range(maxi(0, int(rect.position.x) - 1), mini(_size.x, int(rect.end.x) + 2)):
			if image.get_pixel(x, y).a < 0.5:
				continue
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				removed += 1
	_pixels -= removed
	mass_fraction = float(_pixels) / _initial_pixels
	var center := to_global((rect.get_center() - _half) * PIXEL)
	var outward := (center - global_position).normalized()
	Game.debris(center, _data.debris, 10, 120.0)
	var size_class := 1 if area > 180.0 else 0
	Asteroid.spawn_deferred(_data.rock, size_class, center, outward * randf_range(40.0, 90.0))


func _shatter() -> void:
	if _dead:
		return
	_dead = true
	alive = false
	hp = 0.0
	threat = 0
	remove_from_group(&"planets")
	Game.planets.erase(self)
	for s in _shapes:
		s.set_deferred("disabled", true)
	if post:
		post.obliterate()
	for t in turrets:
		if is_instance_valid(t):
			t.obliterate()
	lost.emit(self)
	Game.play_sound("explode_planet", global_position, 4.0)
	Game.shake(28.0)
	Game.shockwave(global_position, radius * 4.0, Color(3.0, 2.4, 1.8, 1.0), 1.2)
	# Chain of explosions over the remaining pixels, then fragments fly off.
	var points: Array[Vector2] = []
	for i in 400:
		var p := Vector2i(randi() % _size.x, randi() % _size.y)
		if image.get_pixelv(p).a > 0.5:
			points.append(to_global((Vector2(p) - _half) * PIXEL))
		if points.size() >= 18:
			break
	for i in points.size():
		var pt := points[i]
		get_tree().create_timer(i * 0.06).timeout.connect(func() -> void:
			Game.explosion(pt, randf_range(30.0, 60.0), _data.debris))
		var out := (pt - global_position).normalized()
		Asteroid.spawn_deferred(_data.rock, randi_range(0, 2), pt, out * randf_range(60.0, 180.0))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_sprite, "modulate", Color(4.0, 3.0, 2.0, 0.0), 1.0)
	tw.tween_property(_atmo, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(queue_free)


static func _polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5
