class_name Ship
extends CharacterBody2D
## Base for every ship (player, allies, enemies). A controller (_think) sets
## `move_dir` (world-space thrust request) and `face_angle`; the ship keeps its
## inertia, speed decays slowly, rotation eases towards the requested heading.
## Collisions with asteroids/planets bounce the ship and push the rock.
##
## Scene layout (see scenes/ships/*.tscn):
##   Sprite          Sprite2D   - recoloured to the team colour when `team_tinted`
##   CollisionShape2D (circle)  - its radius is used for targeting too
##   Weapon...       Weapon     - any number; Marker2D children mark the muzzles
##   Exhaust...      Marker2D   - engine particles are created at these points

signal hull_changed(hull: float, max_hull: float)
signal destroyed(ship: Ship)

@export_group("Hull")
@export var max_hull := 30.0
@export var impact_threshold := 170.0   ## collision speed above which the ship takes damage
@export var impact_damage := 0.1        ## damage per unit of speed above the threshold
@export var loot := {}                  ## resources an enemy drops, e.g. {"scrap": 4}
@export var explosion_size := 22.0
@export_group("Engine")
@export var thrust := 420.0             ## acceleration, px/s^2
@export var max_speed := 380.0
@export var drag := 0.8                 ## how fast speed fades (inertia)
@export var turn_speed := 4.0           ## rad/s
@export var turn_response := 7.0        ## how quickly turning eases in/out
@export var push_strength := 0.8        ## how hard it shoves meteors
@export var exhaust_width := 3.0
@export var exhaust_strength := 1.0
@export_group("Look")
@export var team_tinted := true         ## recolour grey pixels red/blue by team

var team := 0                  ## Game.Team; set before adding to the tree
var hull := 30.0
var radius := 14.0
var debris_color := Color("7a7a7a")

var move_dir := Vector2.ZERO   ## world-space thrust request, length <= 1
var face_angle := 0.0          ## heading the ship turns towards
var use_direct_turn := false   ## classic control: turn_input drives rotation directly
var turn_input := 0.0
var angular_velocity := 0.0
var alive := true
var weapons: Array[Weapon] = []
var sprite: Sprite2D

var _flash_tween: Tween
var _exhausts: Array[CPUParticles2D] = []


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = Game.body_layer(team)
	collision_mask = Game.L_ASTEROIDS | Game.L_PLANETS
	z_index = 1
	add_to_group(Game.team_group(team))
	add_to_group(&"ships")
	_collect_scene_parts()
	_build()
	hull = max_hull
	face_angle = rotation
	reset_physics_interpolation()


## Picks up the parts laid out in the scene: sprite, collision radius, weapons, exhausts.
func _collect_scene_parts() -> void:
	sprite = get_node_or_null("Sprite") as Sprite2D
	if sprite and team_tinted:
		sprite.material = Game.team_material(team)
	for c in get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is CircleShape2D:
			radius = ((c as CollisionShape2D).shape as CircleShape2D).radius
		elif c is Weapon:
			(c as Weapon).setup(team, self)
			weapons.append(c)
		elif c is Marker2D and c.name.begins_with("Exhaust"):
			add_exhaust((c as Marker2D).position, exhaust_width, exhaust_strength)


## Override for extra setup after the scene parts are collected.
func _build() -> void:
	pass


## Override: controller logic (input or AI).
func _think(_delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_think(delta)
	_move(delta)
	for w in weapons:
		w.tick(delta)
	var thrusting := move_dir.dot(global_transform.x) > 0.25
	for e in _exhausts:
		e.emitting = thrusting


func _move(delta: float) -> void:
	velocity += move_dir.limit_length(1.0) * thrust * delta
	velocity *= exp(-drag * delta)
	var sp := velocity.length()
	if sp > max_speed:
		velocity *= lerpf(1.0, max_speed / sp, 1.0 - exp(-5.0 * delta))
	if global_position.length() > Game.world_radius:
		velocity -= global_position.normalized() * 800.0 * delta

	var target_av: float
	if use_direct_turn:
		target_av = turn_input * turn_speed
	else:
		target_av = clampf(angle_difference(rotation, face_angle) * 5.0, -turn_speed, turn_speed)
	angular_velocity = lerpf(angular_velocity, target_av, 1.0 - exp(-turn_response * delta))
	rotation += angular_velocity * delta

	var col := move_and_collide(velocity * delta)
	if col:
		_resolve_collision(col)


func _resolve_collision(col: KinematicCollision2D) -> void:
	var n := col.get_normal()
	var other := col.get_collider()
	var rel := velocity
	var rb := other as RigidBody2D
	if rb:
		rel -= rb.linear_velocity
	var impact := -rel.dot(n)
	if impact <= 0.0:
		return
	if rb:
		rb.apply_impulse(-n * impact * push_strength, col.get_position() - rb.global_position)
	velocity += n * impact * 1.35
	move_and_collide(col.get_remainder().slide(n))
	if impact > impact_threshold:
		_on_impact(other, impact, col.get_position(), n)


func _on_impact(other: Object, impact: float, point: Vector2, normal: Vector2) -> void:
	take_hit(point, normal, (impact - impact_threshold) * impact_damage, false)
	if other is Asteroid:
		(other as Asteroid).take_hit(point, -normal, impact * 0.08, false)
	Game.play_sound("crunch", point, -8.0)


func take_hit(_point: Vector2, _dir: Vector2, dmg: float, _heavy: bool) -> void:
	if not alive or dmg <= 0.0:
		return
	hull -= dmg
	hull_changed.emit(max(hull, 0.0), max_hull)
	flash()
	if hull <= 0.0:
		die()


func flash(color := Color(3.0, 3.0, 3.0)) -> void:
	if not sprite:
		return
	if _flash_tween:
		_flash_tween.kill()
	sprite.modulate = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)


func die() -> void:
	if not alive:
		return
	alive = false
	remove_from_group(Game.team_group(team))
	remove_from_group(&"ships")
	Game.explosion(global_position, explosion_size, debris_color)
	Game.play_sound("explode_big" if explosion_size > 40.0 else "explode_small", global_position,
			-2.0 if explosion_size > 40.0 else -5.0)
	if team == Game.Team.ENEMY:
		for k in loot:
			Game.drop_resources(global_position, k, loot[k], velocity)
	destroyed.emit(self)
	queue_free()


# ------------------------------------------------------------------ helpers for subclasses
func add_exhaust(local_pos: Vector2, width := 3.0, strength := 1.0) -> CPUParticles2D:
	var e := CPUParticles2D.new()
	e.emitting = false
	e.amount = int(24 * strength) + 8
	e.lifetime = 0.35 * strength + 0.1
	e.local_coords = false
	e.position = local_pos
	e.direction = Vector2.LEFT
	e.spread = 10.0
	e.gravity = Vector2.ZERO
	e.initial_velocity_min = 60.0 * strength
	e.initial_velocity_max = 150.0 * strength
	e.scale_amount_min = 1.0
	e.scale_amount_max = 1.5 + strength
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	e.emission_rect_extents = Vector2(1, width)
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	e.texture = ImageTexture.create_from_image(img)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	var hot := Color(1.6, 3.0, 4.0) if team == Game.Team.ALLY else Color(4.0, 1.8, 0.8)
	ramp.colors = PackedColorArray([hot, Color(hot.r * 0.3, hot.g * 0.3, hot.b * 0.3, 0.7), Color(0.1, 0.05, 0.15, 0.0)])
	e.color_ramp = ramp
	add_child(e)
	_exhausts.append(e)
	return e


## Attaches a weapon created in code (e.g. the player's upgradeable guns).
func mount(w: Weapon) -> Weapon:
	add_child(w)
	w.setup(team, self)
	weapons.append(w)
	return w
