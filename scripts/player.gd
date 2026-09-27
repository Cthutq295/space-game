class_name Player
extends Ship
## Player ship. Control schemes (switchable in the pause menu):
##  0: the nose follows the mouse; W/S thrust forward/back along the nose, A/D strafe.
##  1: classic - A/D turn, W/S thrust along the nose.
##  2: WASD thrusts along screen axes, the nose follows the mouse.
## The main engine (flames + exhaust from the rear nozzle) fires only for forward
## thrust; braking and strafing use small manoeuvring jets on the opposite side.
## LMB blaster, RMB homing missile salvo (locks the enemy nearest to the cursor,
## otherwise a meteor), Space plasma bomb. Weapons come from Arsenal (they level up
## in the station shop), the look lives in scenes/ships/player.tscn:
##   Sprite, CollisionPolygon2D, Flame* (engine flame sprites), Nozzle (Marker2D).

signal died
signal respawned

const LOCK_RADIUS_ENEMY := 450.0
const LOCK_RADIUS_ROCK := 320.0

@export_group("Player")
@export var base_hull := 100.0          ## before "Броня" upgrades
@export var base_thrust := 900.0        ## before "Двигатели" upgrades
@export var base_max_speed := 560.0
@export var reverse_power := 0.6        ## S thrust, share of forward thrust
@export var strafe_power := 0.75        ## A/D thrust, share of forward thrust
@export var respawn_time := 3.0

var blaster: Weapon
var missiles: Weapon
var plasma: Weapon
var lock_target: Node2D

var _invulnerable := 0.0
var _since_damage := 10.0
var _flame_t := 0.0
var _flames: Array[Sprite2D] = []
var _thrust_audio: AudioStreamPlayer
var _thrust_fx: CPUParticles2D
var _rcs_fx: CPUParticles2D
var _lock_marker: Node2D


func _init() -> void:
	team = Game.Team.ALLY


func _build() -> void:
	collision_layer = Game.L_PLAYER
	z_index = 2
	radius = 22.0
	debris_color = Color("7d93b5")
	for c in get_children():
		if c is Sprite2D and c.name.begins_with("Flame"):
			c.visible = false
			_flames.append(c)
	var nozzle := get_node_or_null("Nozzle") as Marker2D
	var nozzle_pos := nozzle.position if nozzle else Vector2(-28, 0)

	# Main engine exhaust: fixed at the rear nozzle, blowing backwards.
	_thrust_fx = add_exhaust(nozzle_pos, 5.0, 1.4)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(4.0, 3.2, 1.8), Color(3.0, 1.3, 0.4), Color(0.9, 0.2, 0.25, 0.7),
			Color(0.2, 0.05, 0.2, 0.0)])
	_thrust_fx.color_ramp = ramp
	# Manoeuvring jets: short white puffs opposite to braking / strafing thrust.
	_rcs_fx = add_exhaust(Vector2.ZERO, 3.0, 0.5)
	var rcs_ramp := Gradient.new()
	rcs_ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	rcs_ramp.colors = PackedColorArray([Color(2.4, 2.6, 3.0), Color(0.8, 0.9, 1.1, 0.6), Color(0.5, 0.5, 0.6, 0.0)])
	_rcs_fx.color_ramp = rcs_ramp
	_exhausts.clear()

	_thrust_audio = AudioStreamPlayer.new()
	_thrust_audio.stream = Game.get_sound("thrust")
	_thrust_audio.volume_db = -60.0
	add_child(_thrust_audio)
	_thrust_audio.play()

	_lock_marker = Node2D.new()
	_lock_marker.top_level = true
	_lock_marker.z_index = 20
	_lock_marker.draw.connect(_draw_lock)
	add_child(_lock_marker)

	apply_upgrades()
	hull = max_hull
	Game.player = self


func apply_upgrades() -> void:
	var u := Game.upgrades
	var old_max := max_hull
	max_hull = base_hull + 25.0 * u.hull
	hull = min(hull + (max_hull - old_max), max_hull)
	thrust = base_thrust * (1.0 + 0.12 * u.engine)
	max_speed = base_max_speed * (1.0 + 0.1 * u.engine)
	for w in weapons:
		w.queue_free()
	weapons.clear()
	blaster = mount(Arsenal.player_blaster(u.blaster))
	missiles = mount(Arsenal.player_missiles(u.missiles))
	plasma = mount(Arsenal.player_plasma())
	hull_changed.emit(hull, max_hull)


func _think(_delta: float) -> void:
	if Game.game_over:
		move_dir = Vector2.ZERO
		return
	var mouse := get_global_mouse_position()
	var fwd := global_transform.x.normalized()
	var right := Vector2(-fwd.y, fwd.x)   # ship's starboard side
	match Game.control_scheme:
		0:
			# Forward vector: W pushes where the nose points, A/D strafe.
			use_direct_turn = false
			face_angle = (mouse - global_position).angle()
			var t := Input.get_axis("brake", "thrust")
			var s := Input.get_axis("turn_left", "turn_right")
			move_dir = fwd * t * (1.0 if t > 0.0 else reverse_power) + right * s * strafe_power
		1:
			use_direct_turn = true
			turn_input = Input.get_axis("turn_left", "turn_right")
			var t := Input.get_axis("brake", "thrust")
			move_dir = fwd * t * (1.0 if t > 0.0 else reverse_power)
		_:
			use_direct_turn = false
			move_dir = Input.get_vector("turn_left", "turn_right", "thrust", "brake")
			face_angle = (mouse - global_position).angle()

	lock_target = _pick_lock(mouse) if missiles.is_ready() else null
	if Game.map_open:
		return
	if Input.is_action_pressed("fire"):
		blaster.try_fire(mouse)
	if Input.is_action_pressed("missile"):
		missiles.try_fire(mouse, _pick_lock(mouse))
	if Input.is_action_pressed("bomb"):
		plasma.try_fire(mouse)


## Enemy nearest to the cursor; if there is none, the meteor nearest to the cursor.
func _pick_lock(mouse: Vector2) -> Node2D:
	var t := Game.find_nearest_hostile(team, mouse, LOCK_RADIUS_ENEMY)
	if t:
		return t
	var best: Node2D = null
	var best_d := LOCK_RADIUS_ROCK * LOCK_RADIUS_ROCK
	for a in get_tree().get_nodes_in_group(&"asteroids"):
		var d := mouse.distance_squared_to((a as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = a
	return best


func _process(delta: float) -> void:
	_since_damage += delta
	if alive and _since_damage > 4.0 and hull < max_hull:
		hull = min(hull + 5.0 * delta, max_hull)
		hull_changed.emit(hull, max_hull)

	var accel := move_dir.limit_length(1.0)
	var local := accel.rotated(-rotation)          # x = forward, y = starboard
	var forward := alive and local.x > 0.3
	_thrust_fx.emitting = forward
	# Everything that is not forward thrust comes from the manoeuvring jets.
	var jets := Vector2(minf(local.x, 0.0), local.y)
	var jets_on := alive and jets.length() > 0.2
	_rcs_fx.emitting = jets_on
	if jets_on:
		_rcs_fx.rotation = jets.angle()                # LEFT-pointing emitter -> blows opposite to thrust
		_rcs_fx.position = -jets.normalized() * 20.0
	_flame_t += delta
	for f in _flames:
		f.visible = forward
		f.frame = int(_flame_t * 20.0) % 3
	var target_db := linear_to_db(0.02 + 0.55 * accel.length()) if alive else -60.0
	_thrust_audio.volume_db = lerp(_thrust_audio.volume_db, target_db, 1.0 - exp(-10.0 * delta))

	if _invulnerable > 0.0:
		_invulnerable -= delta
		sprite.modulate.a = 0.35 if int(_invulnerable * 12.0) % 2 == 0 else 1.0
		if _invulnerable <= 0.0:
			sprite.modulate.a = 1.0
	_lock_marker.queue_redraw()


func _draw_lock() -> void:
	if not alive or not Game.is_alive(lock_target):
		return
	var p := lock_target.global_position
	var r: float = (lock_target.radius if "radius" in lock_target else 20.0) + 10.0
	var col := Color(1.6, 2.6, 3.2, 0.9)
	var l := 8.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := p + Vector2(sx * r, sy * r)
			_lock_marker.draw_line(c, c - Vector2(sx * l, 0), col, 2.0)
			_lock_marker.draw_line(c, c - Vector2(0, sy * l), col, 2.0)


func take_hit(point: Vector2, dir: Vector2, dmg: float, heavy: bool) -> void:
	if _invulnerable > 0.0 or not alive:
		return
	_since_damage = 0.0
	super.take_hit(point, dir, dmg, heavy)
	if alive:
		flash(Color(3.0, 0.6, 0.5))
		Game.play_sound("hurt", null, -12.0)
		Game.shake(min(dmg * 0.4, 8.0))


func die() -> void:
	if not alive:
		return
	alive = false
	hull = 0.0
	Game.explosion(global_position, explosion_size, debris_color)
	Game.play_sound("explode_big", global_position)
	Game.shake(20.0)
	sprite.visible = false
	for f in _flames:
		f.visible = false
	collision_layer = 0
	collision_mask = 0
	remove_from_group(Game.team_group(team))
	velocity = Vector2.ZERO
	died.emit()
	await get_tree().create_timer(respawn_time, false).timeout
	if Game.game_over:
		return
	_respawn()


func _respawn() -> void:
	var spawn := Game.player_spawn   # the level's PlayerSpawn marker
	teleport(spawn)
	hull = max_hull
	alive = true
	_invulnerable = 3.0
	sprite.visible = true
	collision_layer = Game.L_PLAYER
	collision_mask = Game.L_ASTEROIDS | Game.L_PLANETS
	add_to_group(Game.team_group(team))
	hull_changed.emit(hull, max_hull)
	Game.play_sound("respawn")
	respawned.emit()


func teleport(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	reset_physics_interpolation()
	if Game.camera:
		Game.camera.snap_to_target()
