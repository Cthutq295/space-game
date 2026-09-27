class_name Turret
extends Structure
## Stationary gun. "blaster": fast bursts from its magazine, then a reload
## (blaster turrets also shoot down incoming missiles). "missile": homing missiles
## on the launcher rails, fired one by one, then a long reload.
## A ring under the turret shows reload progress.
## Scene layout: Base (Sprite2D), Head (Node2D, rotates) -> HeadSprite + Weapon.
## The gun's numbers (damage, magazine, reload...) are on the Weapon node.

@export_enum("blaster", "missile") var kind := "blaster"
@export var attack_range := 750.0
@export var turn_speed := 3.5          ## rad/s
@export var point_defense_range := 420.0   ## blaster turrets shoot missiles this close

var weapon: Weapon
var target: Node2D

var _head: Node2D
var _think_t := 0.0


func _build() -> void:
	add_to_group(&"turrets")
	_head = get_node("Head")
	weapon = _head.get_node("Weapon")
	weapon.setup(team, self)
	_head.rotation = randf() * TAU


func _physics_process(delta: float) -> void:
	if not alive:
		return
	weapon.tick(delta)
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.25
		target = _choose_target()
	if not Game.is_alive(target):
		target = null
		return
	var aim := _lead(target)
	var want := (aim - global_position).angle()
	_head.global_rotation = rotate_toward(_head.global_rotation, want, turn_speed * delta)
	if absf(angle_difference(_head.global_rotation, want)) < 0.12:
		weapon.try_fire(aim, target)


func _process(_delta: float) -> void:
	queue_redraw()


func _choose_target() -> Node2D:
	if kind == "blaster":
		var best: Node2D = null
		var best_d := point_defense_range * point_defense_range
		for m in get_tree().get_nodes_in_group(&"missiles"):
			var mis := m as Missile
			if mis.team == team:
				continue
			var d := global_position.distance_squared_to(mis.global_position)
			if d < best_d:
				best_d = d
				best = mis
		if best:
			return best
	return Game.find_nearest_hostile(team, global_position, attack_range)


func _lead(t: Node2D) -> Vector2:
	var tv := Vector2.ZERO
	if t is CharacterBody2D:
		tv = (t as CharacterBody2D).velocity
	elif t is Missile:
		tv = (t as Missile).velocity
	var time := global_position.distance_to(t.global_position) / weapon.speed
	return t.global_position + tv * min(time, 1.2)


func _draw() -> void:
	if not alive or not weapon.reloading:
		return
	var col: Color = Game.TEAM_COLORS[team]
	col.a = 0.7
	draw_arc(Vector2.ZERO, radius + 6.0, -PI / 2.0, -PI / 2.0 + TAU * weapon.charge(), 32, col, 2.0)


func _on_alive_changed(v: bool) -> void:
	if weapon:
		weapon.visible = v
