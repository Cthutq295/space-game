class_name DefensePost
extends Structure
## Defense post next to a planet. Builds allied Flies (and heavy gunships at the
## home planet) and replaces the ones that die. Inside its aura the player can
## press E to open the station shop (the game pauses).
## Scene layout: Sprite (slowly rotates), Key (the [E] hint, group "untinted").

@export var max_flies := 3             ## Flies kept alive around the planet
@export var fly_respawn := 16.0        ## seconds between new Flies
@export var max_heavies := 0           ## heavy gunships kept alive (home planet)
@export var heavy_respawn := 60.0
@export var aura_radius := 230.0       ## shop is reachable inside this circle

var extra_flies := 0          ## bought in the shop
var turrets: Array[Turret] = []

var _flies: Array[AIShip] = []
var _heavies: Array[AIShip] = []
var _fly_t := 1.0
var _heavy_t := 3.0
var _pulse := randf() * 10.0
var _sprite: Sprite2D
var _key: Sprite2D


func _build() -> void:
	add_to_group(&"posts")
	_sprite = get_node("Sprite")
	_key = get_node("Key")
	_key.visible = false


func player_inside() -> bool:
	var p := Game.player
	return p != null and p.alive and p.global_position.distance_to(global_position) < aura_radius


func _physics_process(delta: float) -> void:
	_flies = _flies.filter(func(s) -> bool: return Game.is_alive(s))
	_heavies = _heavies.filter(func(s) -> bool: return Game.is_alive(s))
	if not alive or not Game.is_alive(planet):
		return
	if _flies.size() < max_flies + extra_flies:
		_fly_t -= delta
		if _fly_t <= 0.0:
			_fly_t = fly_respawn
			_flies.append(_spawn("fly"))
	if _heavies.size() < max_heavies:
		_heavy_t -= delta
		if _heavy_t <= 0.0:
			_heavy_t = heavy_respawn
			_heavies.append(_spawn("heavy"))


func _spawn(kind: String) -> AIShip:
	var s := AIShip.create(kind, team)
	s.home_planet = planet
	s.position = global_position + Vector2.from_angle(randf() * TAU) * 30.0
	s.rotation = randf() * TAU
	Game.world.add_child(s)
	Game.shockwave(s.position, 60.0, Color(1.2, 2.2, 3.0, 0.8), 0.3)
	return s


func _process(delta: float) -> void:
	_pulse += delta
	_sprite.rotation += delta * 0.15
	var inside := player_inside()
	_key.visible = inside and not get_tree().paused
	_key.position.y = -72.0 + sin(_pulse * 4.0) * 3.0
	queue_redraw()


## Dashed aura ring that slowly rotates and pulses; brighter while the player is inside.
func _draw() -> void:
	var col: Color = Game.TEAM_COLORS[team] if alive else Color(0.8, 0.35, 0.3)
	var inside := player_inside()
	var a := (0.55 if inside else 0.22) + 0.1 * sin(_pulse * 2.0)
	var segs := 40
	var rot := _pulse * 0.12 - rotation
	for i in segs:
		if i % 2 == 1:
			continue
		var a0 := rot + TAU * i / segs
		draw_arc(Vector2.ZERO, aura_radius, a0, a0 + TAU / segs * 0.8, 4, Color(col, a), 3.0)
	draw_circle(Vector2.ZERO, aura_radius, Color(col, 0.035 if not inside else 0.07))


func destroyed_turrets() -> Array[Turret]:
	var out: Array[Turret] = []
	for t in turrets:
		if is_instance_valid(t) and not t.alive:
			out.append(t)
	return out
