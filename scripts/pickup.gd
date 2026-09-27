class_name Pickup
extends Node2D
## Resource chunk dropped where something was destroyed. Drifts, slows down,
## gets pulled in by the player's magnet, blinks before it disappears.

const TEXTURES := {
	"ore": preload("res://assets/sprites/pickup_ore.png"),
	"scrap": preload("res://assets/sprites/pickup_scrap.png"),
	"crystal": preload("res://assets/sprites/pickup_crystal.png"),
}
const GLOW := {"ore": Color(1.35, 1.2, 1.0), "scrap": Color(1.25, 1.3, 1.4), "crystal": Color(1.9, 1.3, 2.2)}
const LIFETIME := 28.0
const COLLECT_DIST := 28.0

var type := "ore"
var value := 1
var velocity := Vector2.ZERO

var _life := LIFETIME
var _sprite: Sprite2D
var _t := randf() * TAU


func _ready() -> void:
	add_to_group(&"pickups")
	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURES[type]
	_sprite.scale = Vector2(Game.PIXEL, Game.PIXEL)
	_sprite.self_modulate = GLOW[type]
	add_child(_sprite)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	_t += delta
	_sprite.position.y = sin(_t * 3.0) * 2.0
	if _life < 5.0:
		_sprite.visible = fmod(_life, 0.3) > 0.12

	var p := Game.player
	var pulled := false
	if p and p.alive:
		var d := p.global_position - global_position
		var dist := d.length()
		if dist < COLLECT_DIST:
			_collect()
			return
		var mr := Game.magnet_radius()
		if dist < mr:
			pulled = true
			var pull := d / dist * (250.0 + (1.0 - dist / mr) * 900.0) + p.velocity
			velocity = velocity.lerp(pull, 1.0 - exp(-7.0 * delta))
	if not pulled:
		velocity *= exp(-1.3 * delta)
	position += velocity * delta


func _collect() -> void:
	Game.add_resource(type, value)
	Game.play_sound("pickup", null, -12.0, 1.0 + randf() * 0.25, 0.0)
	queue_free()
