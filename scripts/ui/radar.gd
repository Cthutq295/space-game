class_name Radar
extends Control
## Minimap centred on the player. Shows only what is within RANGE: enemies as red
## dots, allies as blue dots, rocks faintly. Planets are always shown - pinned to
## the rim when out of range - and pulse red while under attack.

const RANGE := 3200.0
const BG := Color(0.03, 0.02, 0.08, 0.85)
const RIM := Color(0.4, 0.5, 0.9, 0.7)
const ENEMY := Color(1.0, 0.3, 0.25)
const ALLY := Color(0.35, 0.8, 1.0)
const ROCK := Color(0.6, 0.55, 0.55, 0.35)
const LOOT := Color(1.0, 0.85, 0.4, 0.7)
const THREAT := Color(1.0, 0.2, 0.15)
const DOT_SIZE := {"fly": 2.0, "fighter": 3.0, "corsair": 3.5, "heavy": 4.5, "carrier": 5.5}


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var rad: float = min(size.x, size.y) * 0.5 - 4.0
	var k := rad / RANGE
	var origin := Vector2.ZERO
	if Game.player:
		origin = Game.player.global_position
	var t := Time.get_ticks_msec() / 1000.0
	var rad2 := rad * rad

	draw_circle(c, rad + 3.0, BG)
	draw_arc(c, rad * 0.5, 0.0, TAU, 40, Color(RIM, 0.2), 1.0)
	draw_line(c + Vector2(-rad, 0), c + Vector2(rad, 0), Color(RIM, 0.1), 1.0)
	draw_line(c + Vector2(0, -rad), c + Vector2(0, rad), Color(RIM, 0.1), 1.0)
	# Sector boundary, clipped to the radar disc.
	var b := -origin * k
	var wr := Game.world_radius * k
	if origin.length() > Game.world_radius - RANGE:
		var prev := b + Vector2(wr, 0)
		for i in range(1, 181):
			var cur := b + Vector2.from_angle(TAU * i / 180.0) * wr
			if prev.length() < rad and cur.length() < rad:
				draw_line(c + prev, c + cur, Color(1.0, 0.8, 0.3, 0.4), 1.0)
			prev = cur

	for a in get_tree().get_nodes_in_group(&"asteroids"):
		var p: Vector2 = ((a as Node2D).global_position - origin) * k
		if p.length_squared() < rad2:
			draw_rect(Rect2(c + p, Vector2(1.5, 1.5)), ROCK)
	for a in get_tree().get_nodes_in_group(&"pickups"):
		var p: Vector2 = ((a as Node2D).global_position - origin) * k
		if p.length_squared() < rad2:
			draw_rect(Rect2(c + p, Vector2(1.5, 1.5)), LOOT)

	for pl in Game.planets:
		if not Game.is_alive(pl):
			continue
		var p: Vector2 = (pl.global_position - origin) * k
		var pr: float = max(pl.radius * k, 3.0)
		var pos := c + p
		if p.length() + pr > rad:
			pos = c + p.normalized() * (rad - 5.0)
			pr = 4.0
		draw_circle(pos, pr, pl.map_color)
		if pl.is_home:
			draw_arc(pos, pr + 2.0, 0.0, TAU, 20, Color(1, 1, 1, 0.6), 1.0)
		if pl.threat > 0:
			var speed := 3.0 if pl.threat == 1 else 8.0
			var ph := 0.5 + 0.5 * sin(t * speed)
			draw_arc(pos, pr + 3.0 + 5.0 * ph, 0.0, TAU, 24, Color(THREAT, 0.35 + 0.6 * ph), 2.0)

	for s in get_tree().get_nodes_in_group(&"turrets"):
		_structure_dot(s as Structure, c, origin, k, rad2, 2.5)
	for s in get_tree().get_nodes_in_group(&"posts"):
		_structure_dot(s as Structure, c, origin, k, rad2, 4.0)

	for n in get_tree().get_nodes_in_group(&"ships"):
		if n == Game.player:
			continue
		var ship := n as AIShip
		if ship == null:
			continue
		var p: Vector2 = (ship.global_position - origin) * k
		if p.length_squared() > rad2:
			continue
		var d: float = DOT_SIZE.get(ship.kind, 2.5)
		var col := ENEMY if ship.team == Game.Team.ENEMY else ALLY
		draw_rect(Rect2(c + p - Vector2(d, d) * 0.5, Vector2(d, d)), col)
	for m in get_tree().get_nodes_in_group(&"missiles"):
		var mis := m as Missile
		if mis.team != Game.Team.ENEMY:
			continue
		var p: Vector2 = (mis.global_position - origin) * k
		if p.length_squared() < rad2:
			draw_rect(Rect2(c + p, Vector2(1, 1)), Color(1.0, 0.6, 0.4))

	var pl := Game.player
	if pl and pl.alive:
		var fwd := pl.global_transform.x.normalized()
		var side := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([c + fwd * 6.0, c - fwd * 4.0 + side * 4.0,
				c - fwd * 4.0 - side * 4.0]), Color(0.4, 1.0, 0.9))
	draw_arc(c, rad + 3.0, 0.0, TAU, 64, RIM, 2.0)


func _structure_dot(s: Structure, c: Vector2, origin: Vector2, k: float, rad2: float, d: float) -> void:
	var p := (s.global_position - origin) * k
	if p.length_squared() > rad2:
		return
	var col := ALLY if s.alive else Color(0.45, 0.4, 0.45)
	draw_rect(Rect2(c + p - Vector2(d, d) * 0.5, Vector2(d, d)), Color(col, 0.8), false, 1.0)
