class_name Weapon
extends Node2D
## A gun or launcher mounted on a ship or turret head. Handles cadence (interval),
## magazine and reload. Missile racks can show their missiles on the hardpoints:
## they are launched in a fixed order and regrow one by one while reloading.
##
## In a scene: add Marker2D children to mark the muzzles (barrel tips / missile
## rails); they are used in child order. Without markers the `muzzles` list is used.
## The owning ship/turret calls setup() - that is when the team colour is known.

enum Kind { BOLT, PLASMA, SHELL, MISSILE }

@export var kind := Kind.BOLT
@export var damage := 8.0
@export var planet_damage_mult := 0.3   ## bolts nibble planets, shells/missiles hurt them properly
@export var speed := 1000.0             ## projectile speed (missiles: top speed)
@export var interval := 0.2             ## seconds between shots (fixed, no randomness)
@export var magazine := 0               ## shots before reloading; 0 = unlimited
@export var reload_time := 0.0
@export var count := 1                  ## projectiles per shot (fan)
@export var spread := 0.0               ## total fan angle, radians
@export var inaccuracy := 0.0           ## random jitter, radians
@export var life := 1.2                 ## projectile lifetime, seconds
@export var blast_radius := 0.0         ## > 0: area damage on impact
@export var muzzles: Array[Vector2] = [Vector2(20, 0)]   ## used only if there are no Marker2D children
@export var sound := "laser"
@export var sound_db := -12.0
@export var sound_pitch := 1.0
@export var inherit_velocity := 0.5     ## share of the shooter's velocity added to shots
@export_group("Missiles")
@export var missile_turn := 3.0         ## rad/s
@export var missile_accel := 900.0
@export var missile_life := 6.0
@export var missile_hp := 1.0           ## hits needed to shoot it down
@export var show_rack := false          ## missiles hang visibly on the muzzles
@export var salvo := false              ## one trigger pull empties the magazine at `interval`

var team := 0                           ## Game.Team, set by setup()
var body: Node2D                        ## owner body: excluded from own shots, velocity source
var ammo := 0
var reloading := false

var _cd := 0.0
var _reload_left := 0.0
var _next := 0
var _salvo_active := false
var _salvo_aim := Vector2.ZERO
var _salvo_target: Node2D
var _rack: Array[Sprite2D] = []


## Called by the owning ship / turret once its team is known.
func setup(p_team: int, p_body: Node2D) -> void:
	team = p_team
	body = p_body
	ammo = magazine
	var markers: Array[Vector2] = []
	for c in get_children():
		if c is Marker2D:
			markers.append((c as Marker2D).position)
	if not markers.is_empty():
		muzzles = markers
	if show_rack:
		var tex: Texture2D = preload("res://assets/sprites/missile.png")
		for m in muzzles:
			var s := Sprite2D.new()
			s.texture = tex
			s.scale = Vector2(Game.PIXEL, Game.PIXEL)
			s.position = m
			s.material = Game.team_material(team)
			s.self_modulate = Color(1.5, 1.5, 1.5)
			add_child(s)
			_rack.append(s)


func tick(delta: float) -> void:
	_cd -= delta
	if reloading:
		_reload_left -= delta
		if show_rack:
			var shown := int((1.0 - _reload_left / reload_time) * magazine)
			for i in _rack.size():
				_rack[i].visible = i < shown
		if _reload_left <= 0.0:
			reloading = false
			ammo = magazine
			_next = 0
			for s in _rack:
				s.visible = true
	if _salvo_active:
		if reloading or (magazine > 0 and ammo <= 0):
			_salvo_active = false
		elif _cd <= 0.0:
			if Game.is_alive(_salvo_target):
				_salvo_aim = _salvo_target.global_position
			else:
				# Target died mid-salvo: drop the stale reference, the remaining
				# missiles find a new target themselves.
				_salvo_target = null
			_fire_one(_salvo_aim, _salvo_target)


func is_ready() -> bool:
	return _cd <= 0.0 and not reloading and not _salvo_active and (magazine == 0 or ammo > 0)


## 0..1 for the HUD: magazine fill, or reload progress.
func charge() -> float:
	if reloading:
		return 1.0 - _reload_left / max(reload_time, 0.001)
	if magazine > 0:
		return float(ammo) / magazine
	return clamp(1.0 - _cd / max(interval, 0.001), 0.0, 1.0)


func try_fire(aim: Vector2, target: Node2D = null) -> bool:
	if not is_ready():
		return false
	if salvo:
		_salvo_active = true
		_salvo_target = target
		_salvo_aim = aim
	_fire_one(aim, target)
	return true


func _fire_one(aim: Vector2, target: Node2D) -> void:
	_cd = interval
	var slot := _next % muzzles.size()
	_next += 1
	var origin := to_global(muzzles[slot])
	var dir := (aim - origin).normalized()
	if dir == Vector2.ZERO:
		dir = global_transform.x.normalized()
	var inherited := _body_velocity() * inherit_velocity

	if kind == Kind.MISSILE:
		_launch_missile(origin, dir, target, slot, inherited)
	else:
		for i in count:
			var off := 0.0
			if count > 1:
				off = (float(i) / (count - 1) - 0.5) * spread
			var d := dir.rotated(off + randf_range(-inaccuracy, inaccuracy))
			var b := Bullet.new()
			b.team = team
			b.style = {Kind.BOLT: Bullet.Style.BOLT, Kind.PLASMA: Bullet.Style.PLASMA,
					Kind.SHELL: Bullet.Style.SHELL}[kind]
			b.damage = damage
			b.planet_damage_mult = planet_damage_mult
			b.blast_radius = blast_radius
			b.life = life
			b.velocity = d * speed + inherited
			b.position = origin
			if body is CollisionObject2D:
				b.exclude = [(body as CollisionObject2D).get_rid()]
			Game.world.add_child(b)

	if magazine > 0:
		ammo -= 1
		if show_rack and slot < _rack.size():
			_rack[slot].visible = false
		if ammo <= 0:
			reloading = true
			_reload_left = reload_time
	Game.play_sound(sound, origin, sound_db, sound_pitch)


func _launch_missile(origin: Vector2, dir: Vector2, target: Node2D, slot: int, inherited: Vector2) -> void:
	var m := Missile.new()
	m.team = team
	m.target = target
	m.damage = damage
	m.planet_damage_mult = planet_damage_mult
	m.blast_radius = blast_radius
	m.max_speed = speed
	m.accel = missile_accel
	m.turn_rate = missile_turn
	m.life = missile_life
	m.hp = missile_hp
	# Kick the missile sideways off its rail, then the motor ignites.
	var fwd := global_transform.x.normalized()
	var side := Vector2(-fwd.y, fwd.x) * signf(muzzles[slot].y if muzzles[slot].y != 0.0 else 1.0)
	m.velocity = inherited + side * 110.0 + fwd * 40.0
	m.rotation = fwd.angle() if show_rack else dir.angle()
	m.position = origin
	Game.world.add_child(m)


func _body_velocity() -> Vector2:
	if body is CharacterBody2D:
		return (body as CharacterBody2D).velocity
	if body is RigidBody2D:
		return (body as RigidBody2D).linear_velocity
	return Vector2.ZERO
