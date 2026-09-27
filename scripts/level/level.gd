@tool
class_name Level
extends Node2D
## Root of a level scene (scenes/levels/*.tscn). Put planets, defense posts,
## turrets, asteroid fields and a PlayerSpawn marker inside it - anywhere in the
## tree, folders (plain Node2D) are fine.
##
## When the game starts it:
##  - sets the sector size (enemies arrive from its edge),
##  - links every post/turret to the planet you picked in its `planet` field,
##    or to the nearest planet if you left it empty,
##  - finds the home planet (the one with `is_home` ticked).
## In the editor it draws the sector boundary.

@export var world_radius := 7000.0:
	set(v):
		world_radius = v
		queue_redraw()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	Game.world_radius = world_radius
	var spawn := find_child("PlayerSpawn", true, false) as Node2D
	Game.player_spawn = spawn.global_position if spawn else Vector2.ZERO
	link_defenses()


func planets() -> Array[Planet]:
	var out: Array[Planet] = []
	for n in find_children("*", "Planet", true, false):
		out.append(n)
	return out


func link_defenses() -> void:
	var all := planets()
	for p in all:
		if p.is_home:
			Game.home_planet = p
	for n in find_children("*", "DefensePost", true, false):
		var post := n as DefensePost
		if post.planet == null:
			post.planet = _nearest(all, post.global_position)
		if post.planet:
			post.planet.post = post
	for n in find_children("*", "Turret", true, false):
		var t := n as Turret
		if t.planet == null:
			t.planet = _nearest(all, t.global_position)
		if t.planet:
			t.planet.turrets.append(t)
			if t.planet.post:
				t.planet.post.turrets.append(t)


func _nearest(all: Array[Planet], pos: Vector2) -> Planet:
	var best: Planet = null
	var best_d := INF
	for p in all:
		var d := pos.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_arc(Vector2.ZERO, world_radius, 0.0, TAU, 256, Color(1.0, 0.8, 0.3, 0.8), 6.0)
	draw_line(Vector2(-200, 0), Vector2(200, 0), Color(1, 1, 1, 0.3), 3.0)
	draw_line(Vector2(0, -200), Vector2(0, 200), Color(1, 1, 1, 0.3), 3.0)
