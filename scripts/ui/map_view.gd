class_name MapView
extends Control
## Full sector map (Tab). Mouse wheel zooms around the cursor, dragging scrolls.
## The game keeps running underneath. Enemies are shown only where our sensors
## reach: the player's radar range and around living defense posts.

const POST_SENSOR := 1800.0
const PLANET_NAMES := {"terra": "Терра", "lava": "Вулкан", "ice": "Криос", "toxic": "Токсис", "mars": "Марс"}

var zoom := 1.0
var pan := Vector2.ZERO
var _dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	visible = true
	zoom = 1.0
	pan = Vector2.ZERO
	Game.map_open = true
	Game.play_sound("click")


func close() -> void:
	visible = false
	_dragging = false
	Game.map_open = false


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _scale() -> float:
	return min(size.x, size.y) * 0.45 / Game.world_radius * zoom


func _to_screen(w: Vector2) -> Vector2:
	return size * 0.5 + (w - pan) * _scale()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var before := pan + (mb.position - size * 0.5) / _scale()
		zoom = clampf(zoom * (1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 0.7, 8.0)
		var after := pan + (mb.position - size * 0.5) / _scale()
		pan += before - after
		accept_event()
	elif mb and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		_dragging = mb.pressed
		accept_event()
	var mm := event as InputEventMouseMotion
	if mm and _dragging:
		pan -= mm.relative / _scale()
		pan = pan.limit_length(Game.world_radius)
		accept_event()


func _visible_to_sensors(pos: Vector2) -> bool:
	if Game.player and pos.distance_to(Game.player.global_position) < Radar.RANGE:
		return true
	for p in get_tree().get_nodes_in_group(&"posts"):
		var post := p as DefensePost
		if post.alive and pos.distance_to(post.global_position) < POST_SENSOR:
			return true
	return false


func _draw() -> void:
	var font := UiTheme.font()
	var sc := _scale()
	var t := Time.get_ticks_msec() / 1000.0
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.012, 0.045, 0.9))
	var center := _to_screen(Vector2.ZERO)
	for i in range(1, 5):
		draw_arc(center, Game.world_radius * sc * i / 4.0, 0.0, TAU, 96, Color(0.35, 0.45, 0.9, 0.12), 1.0)
	draw_arc(center, Game.world_radius * sc, 0.0, TAU, 128, Color(1.0, 0.8, 0.3, 0.45), 2.0)

	for a in get_tree().get_nodes_in_group(&"asteroids"):
		var p := _to_screen((a as Node2D).global_position)
		draw_rect(Rect2(p, Vector2(1.5, 1.5)), Radar.ROCK)

	for pl in Game.planets:
		if not Game.is_alive(pl):
			continue
		var p := _to_screen(pl.global_position)
		var pr: float = max(pl.radius * sc, 7.0)
		draw_circle(p, pr, pl.map_color)
		var hp := pl.hp_fraction()
		var hc := UiTheme.GOOD.lerp(UiTheme.BAD, 1.0 - hp)
		draw_arc(p, pr + 5.0, 0.0, TAU, 40, Color(0.2, 0.2, 0.3, 0.7), 3.0)
		draw_arc(p, pr + 5.0, -PI / 2.0, -PI / 2.0 + TAU * hp, 40, hc, 3.0)
		if pl.threat > 0:
			var speed := 3.0 if pl.threat == 1 else 8.0
			var ph := 0.5 + 0.5 * sin(t * speed)
			draw_arc(p, pr + 10.0 + 6.0 * ph, 0.0, TAU, 40, Color(Radar.THREAT, 0.4 + 0.6 * ph), 2.0)
		var pname: String = PLANET_NAMES.get(pl.kind, pl.kind)
		if pl.is_home:
			pname += " ★"
		draw_string(font, p + Vector2(-60, pr + 26), pname, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, UiTheme.TEXT)

	for s in get_tree().get_nodes_in_group(&"posts"):
		var post := s as DefensePost
		var p := _to_screen(post.global_position)
		var col := Radar.ALLY if post.alive else Color(0.5, 0.4, 0.45)
		draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col, false, 2.0)
	for s in get_tree().get_nodes_in_group(&"turrets"):
		var tur := s as Turret
		var p := _to_screen(tur.global_position)
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Radar.ALLY if tur.alive else Color(0.5, 0.4, 0.45))

	for n in get_tree().get_nodes_in_group(&"ships"):
		var ship := n as AIShip
		if ship == null:
			continue
		if ship.team == Game.Team.ENEMY and not _visible_to_sensors(ship.global_position):
			continue
		var d: float = Radar.DOT_SIZE.get(ship.kind, 2.5) + 1.0
		var col := Radar.ENEMY if ship.team == Game.Team.ENEMY else Radar.ALLY
		draw_rect(Rect2(_to_screen(ship.global_position) - Vector2(d, d) * 0.5, Vector2(d, d)), col)

	var pl := Game.player
	if pl and pl.alive:
		var c := _to_screen(pl.global_position)
		var fwd := pl.global_transform.x.normalized()
		var side := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([c + fwd * 9.0, c - fwd * 6.0 + side * 6.0,
				c - fwd * 6.0 - side * 6.0]), Color(0.4, 1.0, 0.9))
		draw_arc(c, Radar.RANGE * sc, 0.0, TAU, 64, Color(0.4, 1.0, 0.9, 0.15), 1.0)

	var wd := Game.director
	if wd:
		var info := "ВОЛНА %d / %d" % [wd.wave, Game.director.victory_wave]
		if wd.waves.size() > 0:
			info += "     атака: %d" % wd.enemies_alive()
		elif wd.wave < Game.director.victory_wave:
			info += "     следующая через %d с" % int(max(wd.next_wave_in, 0.0))
		draw_string(font, Vector2(24, 36), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiTheme.TEXT)
	draw_string(font, Vector2(24, size.y - 24), "колесо — масштаб    перетаскивание — прокрутка    Tab — закрыть",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.DIM)
