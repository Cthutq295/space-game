class_name AIShip
extends Ship
## Computer-controlled ship. One class, five roles:
##  fly     - small and weak. Allies guard their planet; enemy flies escort a carrier.
##  fighter - fast enemy raider with twin blasters: attack runs, overshoot, turn back.
##  corsair - agile mid-size assault ship: 3-round bursts, strafes around its target,
##            changes direction unpredictably, dashes away from missiles, regenerating shield.
##  heavy   - slow gunship with 8 missiles on its wings (both teams).
##  carrier - enemy siege ship: shells planets, escorted by flies it rebuilds in its hangar.

## Each role is a scene in scenes/ships/ - its stats are edited in the Inspector.
const SCENES := {
	"fly": "res://scenes/ships/fly.tscn",
	"fighter": "res://scenes/ships/fighter.tscn",
	"corsair": "res://scenes/ships/corsair.tscn",
	"heavy": "res://scenes/ships/heavy.tscn",
	"carrier": "res://scenes/ships/carrier.tscn",
}
const MAX_ESCORTS := 6
const HANGAR_TIME := 14.0
const SHIELD_REGEN_DELAY := 4.0
const SHIELD_REGEN_RATE := 8.0
const DASH_SPEED := 560.0
const DASH_COOLDOWN := 2.6

@export_enum("fly", "fighter", "corsair", "heavy", "carrier") var kind := "fly"
@export var aggro_range := 800.0     ## how far it notices and chases enemies
@export var max_shield := 0.0        ## regenerating shield (corsair)

var home_planet: Planet        ## allies guard it
var objective: Planet          ## enemies attack it
var leader: AIShip             ## escorts keep formation around it
var formation_offset := Vector2.ZERO
var target: Node2D
var gun: Weapon

var escorts: Array[AIShip] = []
var _think_t := 0.0
var _avoid := Vector2.ZERO
var _avoid_t := 0.0
var _sep := Vector2.ZERO
var _evade_t := 0.0
var _evade_dir := Vector2.ZERO
var _orbit_sign := 1.0
var _lane := 0.0
var _hangar_t := HANGAR_TIME
var shield := 0.0
var _shield_idle := 0.0
var _shield_flash := 0.0
var _jink_t := 0.0
var _strafe_r := 320.0
var _dash_cd := 0.0
var _planet_aim := Vector2.ZERO
var _planet_aim_ms := 0


static var _scene_cache := {}


## Instantiates a ship scene by its id in SCENES (its behaviour is the scene's `kind`).
## Set position etc., then add it to the world.
static func create(scene_id: String, p_team: int) -> AIShip:
	if not _scene_cache.has(scene_id):
		_scene_cache[scene_id] = load(SCENES[scene_id])
	var s: AIShip = (_scene_cache[scene_id] as PackedScene).instantiate()
	s.team = p_team
	return s


static func clear_cache() -> void:
	_scene_cache.clear()


func _build() -> void:
	_orbit_sign = 1.0 if randf() < 0.5 else -1.0
	_lane = randf_range(-60.0, 60.0)
	_think_t = randf() * 0.4
	if not weapons.is_empty():
		gun = weapons[0]
		if kind == "fly":
			gun._cd = randf() * gun.interval   # desync the flock, cadence itself stays fixed
	debris_color = Game.TEAM_COLORS[team].darkened(0.3)
	shield = max_shield


# ------------------------------------------------------------------ brain
func _think(delta: float) -> void:
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.35 + randf() * 0.15
		_retarget()
		_update_separation()
	if target and not Game.is_alive(target):
		target = null
	_avoid_t -= delta
	if _avoid_t <= 0.0:
		_avoid_t = 0.12
		_avoid = _compute_avoidance()

	if max_shield > 0.0:
		_update_shield(delta)
	match kind:
		"fly":
			_think_fly()
		"fighter":
			_think_fighter(delta)
		"corsair":
			_think_corsair(delta)
		"heavy":
			_think_heavy()
		"carrier":
			_think_carrier(delta)
	move_dir = (move_dir + _avoid * 1.6 + _sep).limit_length(1.0)


func _retarget() -> void:
	if team == Game.Team.ENEMY and not Game.is_alive(objective):
		objective = _nearest_planet()
	if kind == "carrier":
		target = null
		return
	var center := global_position
	var reach := aggro_range
	if team == Game.Team.ENEMY and kind == "fly" and Game.is_alive(leader):
		center = leader.global_position   # escorts defend the carrier
		reach = 600.0
	var t := Game.find_nearest_hostile(team, center, reach)
	if t and team == Game.Team.ALLY and Game.is_alive(home_planet):
		# Guards don't chase far away from their planet.
		if t.global_position.distance_to(home_planet.global_position) > home_planet.radius + 1600.0:
			t = null
	target = t


func _think_fly() -> void:
	if target:
		_dogfight(target, 200.0, 0.4)
	elif team == Game.Team.ENEMY and Game.is_alive(leader):
		var slot := leader.global_position + formation_offset.rotated(leader.rotation)
		move_dir = _seek(slot, 140.0)
		face_angle = leader.rotation if global_position.distance_to(slot) < 60.0 else (slot - global_position).angle()
	elif team == Game.Team.ALLY:
		_patrol()
	else:
		_attack_planet(260.0)


func _think_fighter(delta: float) -> void:
	if not target:
		_attack_planet(330.0)
		return
	var to := target.global_position - global_position
	if _evade_t > 0.0:
		# Overshoot past the target, then come around for another run.
		_evade_t -= delta
		move_dir = _evade_dir
		face_angle = velocity.angle()
		return
	move_dir = _seek(target.global_position, 60.0)
	_aim_and_fire(target, 0.3)
	if to.length() < 170.0:
		_evade_t = 1.1
		_evade_dir = to.normalized().rotated(randf_range(-0.7, 0.7))


func _think_heavy() -> void:
	if target:
		var away := (global_position - target.global_position).normalized()
		move_dir = _seek(target.global_position + away * 700.0, 250.0, 0.8)
		face_angle = (target.global_position - global_position).angle()
		if global_position.distance_to(target.global_position) < 1400.0:
			gun.try_fire(target.global_position, target)
	elif team == Game.Team.ALLY:
		_patrol(420.0, 0.4)
	elif Game.is_alive(objective):
		var dir := (global_position - objective.global_position).normalized()
		var stand := objective.global_position + dir * (objective.radius + 620.0)
		move_dir = _seek(stand, 300.0, 0.8)
		var aim := _planet_aim_point(objective)
		face_angle = (aim - global_position).angle()
		if global_position.distance_to(objective.global_position) < objective.radius + 950.0:
			gun.try_fire(aim, objective)


func _think_carrier(delta: float) -> void:
	escorts = escorts.filter(func(e) -> bool: return Game.is_alive(e))
	_hangar_t -= delta
	if _hangar_t <= 0.0 and escorts.size() < MAX_ESCORTS:
		_hangar_t = HANGAR_TIME
		spawn_escort()
	if not Game.is_alive(objective):
		move_dir = Vector2.ZERO
		return
	var dir := (global_position - objective.global_position).normalized()
	var stand := objective.global_position + dir * (objective.radius + 380.0)
	move_dir = _seek(stand, 300.0, 0.8)
	var aim := _planet_aim_point(objective)
	face_angle = (aim - global_position).angle()
	if global_position.distance_to(objective.global_position) < objective.radius + 700.0:
		if absf(angle_difference(rotation, face_angle)) < 0.25:
			gun.try_fire(aim, objective)


func spawn_escort() -> AIShip:
	var f := AIShip.create("fly", team)
	f.leader = self
	f.objective = objective
	var i := escorts.size()
	var ang := TAU * i / MAX_ESCORTS
	f.formation_offset = Vector2.from_angle(ang) * Vector2(110.0, 90.0)
	f.position = global_position + Vector2(-40, 0).rotated(rotation)
	f.rotation = rotation
	Game.world.add_child(f)
	escorts.append(f)
	return f


func _think_corsair(delta: float) -> void:
	_dash_cd -= delta
	_try_dodge_missiles()
	# Unpredictable strafing: flip orbit direction and distance every 1-2 s.
	_jink_t -= delta
	if _jink_t <= 0.0:
		_jink_t = randf_range(0.9, 2.0)
		_orbit_sign = -_orbit_sign if randf() < 0.6 else _orbit_sign
		_strafe_r = randf_range(240.0, 420.0)
	if target:
		move_dir = _seek(_orbit_point(target.global_position, _strafe_r), 90.0)
		_aim_and_fire(target, 0.22)
	elif Game.is_alive(objective):
		var c := objective.global_position
		move_dir = _seek(_orbit_point(c, objective.radius + _strafe_r), 150.0, 0.85)
		var aim := _planet_aim_point(objective)
		face_angle = (aim - global_position).angle()
		if global_position.distance_to(c) < objective.radius + _strafe_r + 300.0 \
				and absf(angle_difference(rotation, face_angle)) < 0.3:
			gun.try_fire(aim)
	else:
		move_dir = Vector2.ZERO


## Sideways burst of speed when a hostile missile gets close.
func _try_dodge_missiles() -> void:
	if _dash_cd > 0.0:
		return
	for m in get_tree().get_nodes_in_group(&"missiles"):
		var mis := m as Missile
		if mis.team == team:
			continue
		var to := mis.global_position - global_position
		if to.length() < 280.0 and mis.velocity.dot(-to) > 0.0:
			_dash(Vector2(-to.y, to.x).normalized() * (1.0 if randf() < 0.5 else -1.0))
			return


func _dash(dir: Vector2) -> void:
	_dash_cd = DASH_COOLDOWN
	velocity += dir * DASH_SPEED
	for e in _exhausts:
		e.restart()


func _update_shield(delta: float) -> void:
	_shield_idle += delta
	if _shield_idle > SHIELD_REGEN_DELAY and shield < max_shield:
		shield = min(shield + SHIELD_REGEN_RATE * delta, max_shield)
	_shield_flash = max(_shield_flash - delta * 4.0, 0.0)
	queue_redraw()


func take_hit(point: Vector2, dir: Vector2, dmg: float, heavy: bool) -> void:
	if not alive:
		return
	if max_shield > 0.0:
		_shield_idle = 0.0
		if shield > 0.0:
			var absorbed: float = min(shield, dmg)
			shield -= absorbed
			dmg -= absorbed
			_shield_flash = 1.0
			if shield <= 0.0 and _dash_cd <= 0.0:
				_dash(Vector2(-dir.y, dir.x))   # shield broke - get out of the line of fire
			if dmg <= 0.0:
				return
	super.take_hit(point, dir, dmg, heavy)


func _draw() -> void:
	if max_shield <= 0.0 or shield <= 0.0:
		return
	var k := shield / max_shield
	var col := Color(3.0, 1.3, 0.7) if team == Game.Team.ENEMY else Color(0.8, 2.0, 3.0)
	col.a = 0.12 + 0.25 * k + 0.5 * _shield_flash
	draw_arc(Vector2.ZERO, radius + 8.0, 0.0, TAU, 28, col, 2.0 + 2.0 * _shield_flash)


## Aim point on what is left of the planet (refreshed twice a second, it ray-casts).
func _planet_aim_point(p: Planet) -> Vector2:
	var now := Time.get_ticks_msec()
	if now >= _planet_aim_ms:
		_planet_aim_ms = now + 500 + randi() % 200
		_planet_aim = p.aim_point(global_position)
	return _planet_aim


# ------------------------------------------------------------------ behaviours
func _dogfight(t: Node2D, orbit_r: float, cone: float) -> void:
	var d := global_position.distance_to(t.global_position)
	if d > orbit_r + 60.0:
		move_dir = _seek(t.global_position, 120.0)
	else:
		move_dir = _seek(_orbit_point(t.global_position, orbit_r), 120.0)
	_aim_and_fire(t, cone)


func _patrol(extra := 250.0, speed_scale := 0.55) -> void:
	if not Game.is_alive(home_planet):
		move_dir = -velocity.normalized() * 0.3
		return
	var r := home_planet.radius + extra + _lane
	move_dir = _seek(_orbit_point(home_planet.global_position, r), 200.0, speed_scale)
	if velocity.length() > 20.0:
		face_angle = velocity.angle()


func _attack_planet(stand_off: float) -> void:
	if not Game.is_alive(objective):
		move_dir = Vector2.ZERO
		return
	var c := objective.global_position
	move_dir = _seek(_orbit_point(c, objective.radius + stand_off + _lane * 0.5), 220.0, 0.75)
	var aim := _planet_aim_point(objective)
	face_angle = (aim - global_position).angle()
	if global_position.distance_to(c) < objective.radius + stand_off + 350.0 \
			and absf(angle_difference(rotation, face_angle)) < 0.4:
		gun.try_fire(aim)


func _aim_and_fire(t: Node2D, cone: float) -> void:
	var aim := _lead(t, gun.speed)
	face_angle = (aim - global_position).angle()
	if global_position.distance_to(t.global_position) < 700.0 \
			and absf(angle_difference(rotation, face_angle)) < cone:
		gun.try_fire(aim, t)


# ------------------------------------------------------------------ steering
## Velocity-matching steering: returns a thrust direction towards `point`, slowing on arrival.
func _seek(point: Vector2, arrive := 150.0, speed_scale := 1.0) -> Vector2:
	var to := point - global_position
	var dist := to.length()
	var desired := Vector2.ZERO
	if dist > 1.0:
		desired = to / dist * max_speed * speed_scale * clampf(dist / arrive, 0.0, 1.0)
	return ((desired - velocity) / (max_speed * 0.5)).limit_length(1.0)


func _orbit_point(center: Vector2, r: float) -> Vector2:
	var ang := (global_position - center).angle() + _orbit_sign * 0.45
	return center + Vector2.from_angle(ang) * r


func _lead(t: Node2D, projectile_speed: float) -> Vector2:
	var tv := Vector2.ZERO
	if t is CharacterBody2D:
		tv = (t as CharacterBody2D).velocity
	elif t is RigidBody2D:
		tv = (t as RigidBody2D).linear_velocity
	var time := global_position.distance_to(t.global_position) / maxf(projectile_speed, 1.0)
	return t.global_position + tv * min(time, 1.5)


func _nearest_planet() -> Planet:
	var best: Planet = null
	var best_d := INF
	for p in Game.planets:
		if Game.is_alive(p):
			var d := global_position.distance_squared_to(p.global_position)
			if d < best_d:
				best_d = d
				best = p
	return best


## Look ahead along the velocity; steer away from rocks and planets in the way.
func _compute_avoidance() -> Vector2:
	var sp := velocity.length()
	if sp < 10.0:
		return Vector2.ZERO
	var dir := velocity / sp
	var look := radius * 2.0 + sp * 0.7
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + dir * look,
			Game.L_ASTEROIDS | Game.L_PLANETS, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector2.ZERO
	var n: Vector2 = hit.normal
	var side := Vector2(-dir.y, dir.x)
	if side.dot(n) < 0.0:
		side = -side
	var urgency := 1.0 - global_position.distance_to(hit.position) / look
	return (n * 0.5 + side).normalized() * clampf(urgency * 2.0, 0.3, 1.0)


func _update_separation() -> void:
	_sep = Vector2.ZERO
	var min_d := radius * 2.0 + 30.0
	for n in get_tree().get_nodes_in_group(Game.team_group(team)):
		if n == self or not n is Ship:
			continue
		var d: Vector2 = global_position - (n as Node2D).global_position
		var l := d.length()
		if l > 0.1 and l < min_d:
			_sep += d / l * (1.0 - l / min_d)
	_sep = _sep.limit_length(0.8)
