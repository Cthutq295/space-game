class_name Asteroid
extends RigidBody2D
## Destructible meteor. Large ones split into medium, medium into small,
## small ones burst into debris.

const SIZE_NAMES := ["s", "m", "l"]
const TEX_SIZE := [14, 24, 40]
const MAX_HP := [10.0, 32.0, 80.0]
const MASS := [0.6, 2.5, 8.0]
const LOOT := [1, 3, 6]
const KINDS := ["rock", "iron", "ice", "crystal"]
const KIND_COLOR := {
	"rock": Color("957a66"), "iron": Color("7b88a0"), "ice": Color("8fd0ee"), "crystal": Color("b659ff"),
}

## Rim colour per kind: pale, slightly tinted; crystals exceed 1.0 so they glow a little.
const RIM_COLOR := {
	"rock": Color(0.95, 0.85, 0.75, 0.55), "iron": Color(0.8, 0.88, 1.0, 0.55),
	"ice": Color(0.7, 0.95, 1.1, 0.6), "crystal": Color(1.5, 0.8, 1.9, 0.7),
}
const RIM_TEXELS := 1.6   ## rim width in texture pixels

static var _textures := {}
static var _rim_materials := {}

var kind := "rock"
var size_class := 2
var hp := 10.0
var radius := 10.0

var _sprite: Sprite2D
var _dead := false
var _flash_tween: Tween


static func create(p_kind: String, p_size: int, pos: Vector2, vel: Vector2) -> Asteroid:
	var a := Asteroid.new()
	a.kind = p_kind
	a.size_class = p_size
	a.position = pos
	a.linear_velocity = vel
	a.rotation = randf() * TAU
	a.angular_velocity = randf_range(-1.6, 1.6) / (p_size + 1)
	return a


static func _get_texture(p_kind: String, p_size: int, variant: int) -> Texture2D:
	var key := "%s_%s%d" % [p_kind, SIZE_NAMES[p_size], variant]
	if not _textures.has(key):
		_textures[key] = load("res://assets/sprites/asteroid_%s.png" % key)
	return _textures[key]


static func _rim_material(p_kind: String) -> ShaderMaterial:
	if not _rim_materials.has(p_kind):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/silhouette.gdshader")
		m.set_shader_parameter("tint", RIM_COLOR[p_kind])
		_rim_materials[p_kind] = m
	return _rim_materials[p_kind]


static func clear_cache() -> void:
	_textures.clear()
	_rim_materials.clear()


func _ready() -> void:
	add_to_group("asteroids")
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.05
	collision_layer = Game.L_ASTEROIDS
	collision_mask = Game.L_PLAYER | Game.L_ASTEROIDS | Game.L_PLANETS | Game.L_ALLIES | Game.L_ENEMIES
	mass = MASS[size_class]
	hp = MAX_HP[size_class]
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.4
	mat.friction = 0.3
	physics_material_override = mat

	radius = TEX_SIZE[size_class] * 0.5 * Game.PIXEL * 0.8
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	cs.shape = circle
	add_child(cs)

	var tex := _get_texture(kind, size_class, randi() % 3)
	# Light rim behind the rock so it stands out from the dark background.
	var rim := Sprite2D.new()
	rim.texture = tex
	var grow: float = (TEX_SIZE[size_class] + RIM_TEXELS * 2.0) / TEX_SIZE[size_class]
	rim.scale = Vector2.ONE * Game.PIXEL * grow
	rim.material = _rim_material(kind)
	add_child(rim)
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.scale = Vector2(Game.PIXEL, Game.PIXEL)
	add_child(_sprite)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Keep drifting rocks inside the sector.
	var p := state.transform.origin
	if p.length() > Game.world_radius * 1.1:
		state.linear_velocity -= p.normalized() * 60.0 * state.step


func take_hit(point: Vector2, dir: Vector2, dmg: float, _heavy: bool) -> void:
	if _dead:
		return
	hp -= dmg
	apply_impulse(dir * dmg * (3.0 + size_class * 3.0), point - global_position)
	Game.debris(point, KIND_COLOR[kind], 3 + size_class * 2, 120.0)
	_flash()
	if hp <= 0.0:
		_destroy(dir)


func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_sprite.modulate = Color(3.0, 3.0, 3.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_sprite, "modulate", Color.WHITE, 0.12)


func _destroy(dir: Vector2) -> void:
	_dead = true
	if kind == "crystal":
		Game.drop_resources(global_position, "crystal", size_class + 1, linear_velocity)
	else:
		Game.drop_resources(global_position, "ore", LOOT[size_class], linear_velocity)
	Game.explosion(global_position, radius * 1.1, KIND_COLOR[kind])
	if size_class == 2:
		Game.play_sound("explode_big", global_position, -2.0)
	else:
		Game.play_sound("explode_small", global_position, -4.0 + size_class * 2.0)
	if size_class > 0:
		var count := randi_range(2, 3)
		for i in count:
			var ang := TAU * i / count + randf() * 0.7
			var off := Vector2.RIGHT.rotated(ang) * radius * 0.55
			var vel := linear_velocity + off.normalized() * randf_range(40.0, 120.0) + dir * 50.0
			spawn_deferred(kind, size_class - 1, global_position + off, vel)
		if size_class == 2:
			spawn_deferred(kind, 0, global_position, linear_velocity + dir * 90.0)
	queue_free()


static func spawn_deferred(p_kind: String, p_size: int, pos: Vector2, vel: Vector2) -> void:
	var a := create(p_kind, p_size, pos, vel)
	Game.world.add_child.call_deferred(a)
