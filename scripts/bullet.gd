class_name Bullet
extends Node2D
## Fast projectile. Moves with a ray cast each physics step so it never tunnels.
## HDR modulate (> 1.0) makes it glow through the bloom pass.
## Allied projectiles don't damage planets (they are ours) - they just spark on them.

enum Style { BOLT, PLASMA, SHELL }

var style := Style.BOLT
var team := Game.Team.ALLY
var velocity := Vector2.ZERO
var damage := 10.0
var planet_damage_mult := 1.0
var blast_radius := 0.0
var life := 1.3
var exclude: Array[RID] = []

var _sprite: Sprite2D


func _ready() -> void:
	z_index = 3
	rotation = velocity.angle()
	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(Game.PIXEL, Game.PIXEL)
	match style:
		Style.BOLT:
			_sprite.texture = preload("res://assets/sprites/bolt.png")
			_sprite.self_modulate = Game.BOLT_COLORS[team]
		Style.PLASMA, Style.SHELL:
			var ally := style == Style.PLASMA
			_sprite.texture = preload("res://assets/sprites/plasma.png")
			_sprite.self_modulate = Color(3.2, 1.5, 4.0) if ally else Color(4.0, 1.4, 0.8)
			var glow := Sprite2D.new()
			glow.texture = preload("res://assets/sprites/glow.png")
			glow.modulate = Color(1.6, 0.5, 2.2, 0.55) if ally else Color(2.2, 0.6, 0.3, 0.6)
			glow.scale = Vector2(1.6, 1.6)
			add_child(glow)
	add_child(_sprite)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters2D.create(from, to, Game.hostile_mask(team), exclude)
	query.collide_with_areas = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_impact(hit.position, hit.collider, hit.normal)
		return
	global_position = to
	if style != Style.BOLT:
		_sprite.rotation += delta * 12.0
	life -= delta
	if life <= 0.0:
		if blast_radius > 0.0:
			_detonate(global_position, null, velocity.normalized())
		queue_free()


func _impact(point: Vector2, collider: Object, normal: Vector2) -> void:
	var dir := velocity.normalized()
	if blast_radius > 0.0:
		_detonate(point, collider, dir)
	else:
		_apply(collider, point, dir, damage, false)
		Game.sparks(point, normal, 8, team)
		Game.play_sound("hit", point, -14.0)
	queue_free()


func _apply(c: Object, point: Vector2, dir: Vector2, dmg: float, heavy: bool) -> void:
	if c == null or not is_instance_valid(c) or not c.has_method("take_hit"):
		return
	if c is Planet:
		if team == Game.Team.ALLY:
			return
		dmg *= planet_damage_mult
	c.take_hit(point, dir, dmg, heavy)


func _detonate(point: Vector2, direct: Object, dir: Vector2) -> void:
	_apply(direct, point, dir, damage, true)
	Explosives.blast(get_world_2d(), point, blast_radius, damage * 0.7, team, direct)
	var ally := team == Game.Team.ALLY
	Game.explosion(point, blast_radius * 0.35, Color("c77dff") if ally else Color("ff7a4a"), ally)
	Game.play_sound("explode_small", point, 0.0, 0.8)
