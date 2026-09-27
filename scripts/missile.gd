class_name Missile
extends Area2D
## Homing missile. Kicked off its rail, ignites after a short delay, then turns
## towards a lead point on its target with a limited turn rate (so it can miss
## and loop back). It is a hittable Area2D: bullets can shoot it down.
## Explodes on impact, when shot, near its target, or when its fuel runs out.

const IGNITE_DELAY := 0.22

var team := Game.Team.ALLY
var target: Node2D
var damage := 20.0
var planet_damage_mult := 1.0
var blast_radius := 55.0
var velocity := Vector2.ZERO
var accel := 900.0
var max_speed := 600.0
var turn_rate := 3.0
var life := 6.0
var hp := 1.0

var _ignite := IGNITE_DELAY
var _dead := false
var _search_t := 0.0
var _planet_aim := Vector2.ZERO
var _planet_aim_t := 0.0
var _trail: CPUParticles2D
var _flame: Sprite2D


func _ready() -> void:
	z_index = 3
	add_to_group(&"missiles")
	collision_layer = Game.missile_layer(team)
	collision_mask = 0
	monitoring = false
	monitorable = true
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 7.0
	cs.shape = circle
	add_child(cs)

	_trail = CPUParticles2D.new()
	_trail.amount = 40
	_trail.lifetime = 0.7
	_trail.local_coords = false
	_trail.emitting = false
	_trail.position = Vector2(-8, 0)
	_trail.direction = Vector2.LEFT
	_trail.spread = 12.0
	_trail.gravity = Vector2.ZERO
	_trail.initial_velocity_min = 20.0
	_trail.initial_velocity_max = 60.0
	_trail.scale_amount_min = 1.5
	_trail.scale_amount_max = 3.0
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_trail.texture = ImageTexture.create_from_image(img)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 1.0])
	var hot := Color(4.0, 3.0, 1.6) if team == Game.Team.ALLY else Color(4.5, 1.6, 0.8)
	ramp.colors = PackedColorArray([hot, Color(1.4, 0.6, 0.3, 0.9), Color(0.45, 0.42, 0.5, 0.5),
			Color(0.3, 0.3, 0.35, 0.0)])
	_trail.color_ramp = ramp
	add_child(_trail)

	var s := Sprite2D.new()
	s.texture = preload("res://assets/sprites/missile.png")
	s.scale = Vector2(Game.PIXEL, Game.PIXEL)
	s.material = Game.team_material(team)
	add_child(s)
	_flame = Sprite2D.new()
	_flame.texture = preload("res://assets/sprites/glow.png")
	_flame.scale = Vector2(0.35, 0.35)
	_flame.position = Vector2(-8, 0)
	_flame.modulate = hot
	_flame.visible = false
	add_child(_flame)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	life -= delta
	if life <= 0.0:
		explode(global_position)
		return

	if _ignite > 0.0:
		_ignite -= delta
		velocity *= exp(-2.5 * delta)
		if _ignite <= 0.0:
			_trail.emitting = true
			_flame.visible = true
	else:
		if not Game.is_alive(target):
			target = null
			_search_t -= delta
			if _search_t <= 0.0:
				_search_t = 0.25
				target = _find_target()
		var desired := rotation
		if target:
			desired = (_lead_point() - global_position).angle()
		rotation = rotate_toward(rotation, desired, turn_rate * delta)
		var fwd := Vector2.from_angle(rotation)
		velocity += fwd * accel * delta
		var lateral := velocity - fwd * velocity.dot(fwd)
		velocity -= lateral * min(1.0, 2.5 * delta)
		velocity = velocity.limit_length(max_speed)
		# Proximity fuse (not for planets: those are hit on their surface).
		if target and not target is Planet:
			var r: float = target.radius if "radius" in target else 16.0
			if global_position.distance_to(target.global_position) < r + 14.0:
				explode(global_position)
				return

	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters2D.create(from, to, Game.hostile_mask(team), [get_rid()])
	q.collide_with_areas = true
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Object = hit.collider
		if c and c.has_method("take_hit") and not (c is Planet and team == Game.Team.ALLY):
			var dmg := damage * (planet_damage_mult if c is Planet else 1.0)
			c.take_hit(hit.position, velocity.normalized(), dmg, c is Planet)
		explode(hit.position, c)
		return
	global_position = to


func _lead_point() -> Vector2:
	if target is Planet:
		# Home in on remaining mass, not the centre (it may be a hole by now).
		_planet_aim_t -= get_physics_process_delta_time()
		if _planet_aim_t <= 0.0:
			_planet_aim_t = 0.4
			_planet_aim = (target as Planet).aim_point(global_position)
		return _planet_aim
	var tv := Vector2.ZERO
	if target is CharacterBody2D:
		tv = (target as CharacterBody2D).velocity
	elif target is RigidBody2D:
		tv = (target as RigidBody2D).linear_velocity
	var dist := global_position.distance_to(target.global_position)
	var t: float = min(dist / max(velocity.length(), 250.0), 1.5)
	return target.global_position + tv * t * 0.8


func _find_target() -> Node2D:
	var t := Game.find_nearest_hostile(team, global_position, 900.0)
	if t or team == Game.Team.ENEMY:
		return t
	# Allied missiles fall back to the nearest meteor.
	var best: Node2D = null
	var best_d := 600.0 * 600.0
	for a in get_tree().get_nodes_in_group(&"asteroids"):
		var d := global_position.distance_squared_to((a as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = a
	return best


## Missiles can be shot down.
func take_hit(_point: Vector2, _dir: Vector2, dmg: float, _heavy: bool) -> void:
	if _dead:
		return
	hp -= dmg
	if hp <= 0.0:
		explode(global_position)


func explode(at: Vector2, skip: Object = null) -> void:
	if _dead:
		return
	_dead = true
	set_deferred("monitorable", false)
	Explosives.blast(get_world_2d(), at, blast_radius, damage * 0.6, team, skip)
	Game.explosion(at, 22.0, Color("ffb070"))
	Game.play_sound("explode_small", at, -7.0, 1.2)
	queue_free()
