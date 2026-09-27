class_name Structure
extends StaticBody2D
## Base for stationary allied buildings (defense posts, turrets):
## hull, hit flash, destruction into a wreck and rebuilding.
## Scene layout: a CollisionShape2D (circle) plus Sprite2D children; every Sprite2D
## in the scene gets the team colour and darkens when the building is wrecked.

signal destroyed

@export var max_hull := 150.0
## The planet this building belongs to. Leave empty: the level links it to the
## nearest planet when the game starts.
@export var planet: Planet

var team := 0   ## Game.Team.ALLY
var hull := 150.0
var radius := 20.0
var alive := true

var _visuals: Array[CanvasItem] = []
var _flash_tween: Tween


func _ready() -> void:
	z_index = -1
	collision_mask = 0
	team = Game.Team.ALLY
	for c in find_children("*", "", true, false):
		if c is CollisionShape2D and (c as CollisionShape2D).shape is CircleShape2D:
			radius = ((c as CollisionShape2D).shape as CircleShape2D).radius
		elif c is Sprite2D and not c.is_in_group(&"untinted"):
			(c as Sprite2D).material = Game.team_material(team)
			_visuals.append(c)
	_build()
	_set_alive(true)
	hull = max_hull


## Override.
func _build() -> void:
	pass


func take_hit(_point: Vector2, _dir: Vector2, dmg: float, _heavy: bool) -> void:
	if not alive:
		return
	hull -= dmg
	if _flash_tween:
		_flash_tween.kill()
	modulate = Color(2.5, 2.5, 2.5)
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.15)
	if hull <= 0.0:
		destroy()


func destroy() -> void:
	if not alive:
		return
	_set_alive(false)
	Game.explosion(global_position, radius * 1.6, Color("58647e"))
	Game.play_sound("explode_big", global_position, -4.0)
	destroyed.emit()


func rebuild() -> void:
	if alive:
		return
	hull = max_hull
	_set_alive(true)
	Game.shockwave(global_position, radius * 3.0, Color(1.2, 2.2, 3.0, 0.9))


func _set_alive(v: bool) -> void:
	alive = v
	if v:
		add_to_group(Game.team_group(team))
		collision_layer = Game.body_layer(team)
		for s in _visuals:
			s.modulate = Color.WHITE
	else:
		remove_from_group(Game.team_group(team))
		set_deferred("collision_layer", 0)
		for s in _visuals:
			s.modulate = Color(0.35, 0.3, 0.35)
	_on_alive_changed(v)


## Override.
func _on_alive_changed(_v: bool) -> void:
	pass


## Removes the building for good (its planet is gone).
func obliterate() -> void:
	if alive:
		Game.explosion(global_position, radius * 1.6, Color("58647e"))
	remove_from_group(Game.team_group(team))
	queue_free()
