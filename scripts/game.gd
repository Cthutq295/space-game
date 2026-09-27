extends Node
## Global state (autoload "Game"): teams & collision layers, resources, upgrades,
## input map, audio and visual effects.

signal resources_changed
signal game_ended(victory: bool)

enum Team { ALLY, ENEMY }

const PIXEL := 2.0

# Physics layers (bit values).
const L_PLAYER := 1
const L_ASTEROIDS := 2
const L_PLANETS := 4
const L_ALLIES := 8
const L_ENEMIES := 16
const L_ALLY_MISSILES := 32
const L_ENEMY_MISSILES := 64

const TEAM_COLORS := {Team.ALLY: Color(0.35, 0.78, 1.0), Team.ENEMY: Color(1.0, 0.28, 0.25)}
## HDR colours for projectiles of each team (> 1.0 = bloom).
const BOLT_COLORS := {Team.ALLY: Color(1.7, 2.8, 3.6), Team.ENEMY: Color(3.6, 1.2, 0.9)}

const SOUND_NAMES := ["laser", "plasma", "hit", "crunch", "explode_small", "explode_big",
		"explode_planet", "hurt", "respawn", "thrust", "alarm", "pickup", "missile", "buy", "error", "click"]
const MAX_VOICES_PER_SOUND := 6

const RESOURCE_TYPES := ["ore", "scrap", "crystal"]
const MAX_PICKUPS := 260

var world: Node2D
var camera: GameCamera
var player: Player
var hud: Hud
var planets: Array[Planet] = []
var home_planet: Planet
var world_radius := 7000.0          ## set by the level (Level.world_radius)
var player_spawn := Vector2.ZERO    ## set by the level (its PlayerSpawn marker)
var director: WaveDirector

var resources := {"ore": 0, "scrap": 0, "crystal": 0}
var upgrades := {"hull": 0, "blaster": 0, "missiles": 0, "engine": 0, "magnet": 0}
## 0 = nose follows the mouse, W/S thrust along the nose, A/D strafe.
## 1 = classic (A/D turn, W/S thrust). 2 = WASD along screen axes.
var control_scheme := 0
var map_open := false
var game_over := false

var music: AudioStreamPlayer

var _sounds := {}
var _voices := {}
var _pixel_tex: Texture2D
var _ring_tex: Texture2D = preload("res://assets/sprites/ring.png")
var _glow_tex: Texture2D = preload("res://assets/sprites/glow.png")
var _fire_ramp := Gradient.new()
var _spark_ramp := Gradient.new()
var _red_spark_ramp := Gradient.new()
var _plasma_ramp := Gradient.new()
var _team_materials := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_pixel_tex = ImageTexture.create_from_image(img)

	_fire_ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 0.65, 1.0])
	_fire_ramp.colors = PackedColorArray([Color(6, 5.5, 4.5), Color(5, 2.8, 1.0), Color(2.6, 0.8, 0.25),
			Color(0.5, 0.12, 0.12, 0.8), Color(0.12, 0.05, 0.1, 0.0)])
	_spark_ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	_spark_ramp.colors = PackedColorArray([Color(4, 5, 6), Color(1.2, 2.6, 3.6), Color(0.2, 0.6, 1.0, 0.0)])
	_red_spark_ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	_red_spark_ramp.colors = PackedColorArray([Color(6, 4, 3), Color(3.6, 1.0, 0.6), Color(1.0, 0.2, 0.1, 0.0)])
	_plasma_ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.6, 1.0])
	_plasma_ramp.colors = PackedColorArray([Color(6, 5, 6), Color(4, 1.4, 5), Color(1.4, 0.3, 2.2, 0.8),
			Color(0.2, 0.05, 0.4, 0.0)])

	for n in SOUND_NAMES:
		_sounds[n] = load("res://assets/audio/%s.wav" % n)
		_voices[n] = 0

	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/audio/music.wav")
	music.volume_db = -6.0
	music.finished.connect(music.play)
	add_child(music)


func _setup_input() -> void:
	# Physical keycodes: WASD works on any keyboard layout (including Russian).
	_add_key("thrust", KEY_W)
	_add_key("thrust", KEY_UP)
	_add_key("brake", KEY_S)
	_add_key("brake", KEY_DOWN)
	_add_key("turn_left", KEY_A)
	_add_key("turn_left", KEY_LEFT)
	_add_key("turn_right", KEY_D)
	_add_key("turn_right", KEY_RIGHT)
	_add_key("bomb", KEY_SPACE)
	_add_mouse("fire", MOUSE_BUTTON_LEFT)
	_add_mouse("missile", MOUSE_BUTTON_RIGHT)
	_add_key("interact", KEY_E)
	_add_key("map", KEY_TAB)
	_add_key("pause", KEY_ESCAPE)
	_add_mouse("zoom_in", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse("zoom_out", MOUSE_BUTTON_WHEEL_DOWN)
	_add_key("zoom_in", KEY_EQUAL)
	_add_key("zoom_in", KEY_KP_ADD)
	_add_key("zoom_out", KEY_MINUS)
	_add_key("zoom_out", KEY_KP_SUBTRACT)
	_add_key("toggle_music", KEY_M)
	_add_key("toggle_fullscreen", KEY_F11)


func _add_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _add_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_music"):
		music.stream_paused = not music.stream_paused
	elif event.is_action_pressed("toggle_fullscreen"):
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


func start_music() -> void:
	if not music.playing:
		music.play()


func get_sound(sound_name: String) -> AudioStream:
	return _sounds[sound_name]


func reset() -> void:
	planets.clear()
	home_planet = null
	resources = {"ore": 0, "scrap": 0, "crystal": 0}
	upgrades = {"hull": 0, "blaster": 0, "missiles": 0, "engine": 0, "magnet": 0}
	map_open = false
	game_over = false
	for n in SOUND_NAMES:
		_voices[n] = 0


func end_game(victory: bool) -> void:
	if game_over:
		return
	game_over = true
	game_ended.emit(victory)


# ------------------------------------------------------------------ teams
func hostile_team(team: int) -> int:
	return Team.ENEMY if team == Team.ALLY else Team.ALLY


func team_group(team: int) -> StringName:
	return &"team_ally" if team == Team.ALLY else &"team_enemy"


func body_layer(team: int) -> int:
	return L_ALLIES if team == Team.ALLY else L_ENEMIES


func missile_layer(team: int) -> int:
	return L_ALLY_MISSILES if team == Team.ALLY else L_ENEMY_MISSILES


## Everything a projectile of `team` can hit.
func hostile_mask(team: int) -> int:
	if team == Team.ALLY:
		return L_ASTEROIDS | L_PLANETS | L_ENEMIES | L_ENEMY_MISSILES
	return L_ASTEROIDS | L_PLANETS | L_PLAYER | L_ALLIES | L_ALLY_MISSILES


## Team recolour materials (materials/team_ally.tres, team_enemy.tres).
func team_material(team: int) -> ShaderMaterial:
	if not _team_materials.has(team):
		_team_materials[team] = load("res://materials/team_%s.tres" % ("ally" if team == Team.ALLY else "enemy"))
	return _team_materials[team]


## Nearest living unit hostile to `team` within `max_dist` (ships, turrets, posts, player).
func find_nearest_hostile(team: int, pos: Vector2, max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist * max_dist
	for n in get_tree().get_nodes_in_group(team_group(hostile_team(team))):
		var u := n as Node2D
		var d := pos.distance_squared_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best


func is_alive(n) -> bool:
	if n == null or not is_instance_valid(n) or (n as Node).is_queued_for_deletion():
		return false
	return not ("alive" in n) or n.alive


# ------------------------------------------------------------------ economy
func add_resource(type: String, amount: int) -> void:
	resources[type] += amount
	resources_changed.emit()


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if resources[k] < cost[k]:
			return false
	return true


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		resources[k] -= cost[k]
	resources_changed.emit()
	return true


func magnet_radius() -> float:
	return 170.0 + 100.0 * upgrades.magnet


## Scatters `amount` of a resource as pickups flying out from `pos`.
func drop_resources(pos: Vector2, type: String, amount: int, base_vel := Vector2.ZERO) -> void:
	if world == null or amount <= 0:
		return
	var existing := get_tree().get_node_count_in_group(&"pickups")
	var chunks: int = clamp(amount, 1, 6)
	if existing > MAX_PICKUPS:
		chunks = 1
	var per := amount / chunks
	var extra := amount % chunks
	for i in chunks:
		var p := Pickup.new()
		p.type = type
		p.value = per + (1 if i < extra else 0)
		p.position = pos
		p.velocity = base_vel * 0.5 + Vector2.from_angle(randf() * TAU) * randf_range(60.0, 200.0)
		world.add_child.call_deferred(p)


# ------------------------------------------------------------------ audio
func play_sound(sound_name: String, pos = null, volume_db := 0.0, pitch := 1.0, pitch_rand := 0.08) -> void:
	if _voices[sound_name] >= MAX_VOICES_PER_SOUND:
		return
	var p: Node
	if pos == null or world == null:
		var a := AudioStreamPlayer.new()
		a.stream = _sounds[sound_name]
		a.volume_db = volume_db
		a.pitch_scale = pitch * randf_range(1.0 - pitch_rand, 1.0 + pitch_rand)
		add_child(a)
		a.play()
		p = a
	else:
		var a2 := AudioStreamPlayer2D.new()
		a2.stream = _sounds[sound_name]
		a2.volume_db = volume_db
		a2.pitch_scale = pitch * randf_range(1.0 - pitch_rand, 1.0 + pitch_rand)
		a2.max_distance = 2600.0
		a2.attenuation = 1.4
		a2.position = pos
		world.add_child(a2)
		a2.play()
		p = a2
	_voices[sound_name] += 1
	p.finished.connect(func() -> void:
		_voices[sound_name] -= 1
		p.queue_free())


# ------------------------------------------------------------------ effects
func shake(amount: float) -> void:
	if camera:
		camera.add_shake(amount)


func _particles(pos: Vector2, amount: int, speed_min: float, speed_max: float, life: float,
		size_min: float, size_max: float, ramp: Gradient, color := Color.WHITE,
		dir := Vector2.RIGHT, spread := 180.0, damping := 0.0) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _pixel_tex
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = max(amount, 1)
	p.lifetime = life
	p.lifetime_randomness = 0.5
	p.direction = dir
	p.spread = spread
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.damping_min = damping * 0.5
	p.damping_max = damping
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	p.angle_min = 0.0
	p.angle_max = 0.0
	p.color = color
	if ramp:
		p.color_ramp = ramp
	p.position = pos
	world.add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)
	return p


func sparks(pos: Vector2, normal: Vector2, count := 8, team := Team.ALLY) -> void:
	if world == null:
		return
	var ramp := _spark_ramp if team == Team.ALLY else _red_spark_ramp
	_particles(pos, count, 120.0, 380.0, 0.28, 0.5, 1.2, ramp, Color.WHITE, normal, 55.0, 300.0)
	var fc := Color(2.2, 3.2, 4.0, 0.9) if team == Team.ALLY else Color(4.0, 1.6, 1.0, 0.9)
	_flash(pos, 0.45, fc, 0.1)


func debris(pos: Vector2, color: Color, count := 6, speed := 160.0) -> void:
	if world == null or count <= 0:
		return
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	ramp.colors = PackedColorArray([color.lightened(0.2), color, Color(color, 0.0)])
	_particles(pos, count, speed * 0.3, speed, 0.9, 0.8, 2.2, ramp, Color.WHITE, Vector2.RIGHT, 180.0, 60.0)


func explosion(pos: Vector2, radius: float, debris_color: Color, plasma := false) -> void:
	if world == null:
		return
	var ramp := _plasma_ramp if plasma else _fire_ramp
	var n := int(clamp(radius * 1.2, 14, 140))
	_particles(pos, n, radius * 1.2, radius * 5.0, 0.7, 1.0, 3.0, ramp, Color.WHITE, Vector2.RIGHT, 180.0, radius * 3.0)
	_particles(pos, n / 2, radius * 0.5, radius * 2.0, 1.1, 1.5, 4.0, ramp, Color.WHITE, Vector2.RIGHT, 180.0, radius)
	debris(pos, debris_color, int(n * 0.6), radius * 4.0)
	var flash_col := Color(3.5, 1.8, 4.5) if plasma else Color(4.5, 3.2, 2.0)
	_flash(pos, radius / 10.0, flash_col, 0.22)
	shockwave(pos, radius * 2.6, Color(2.0, 1.2, 3.0, 0.9) if plasma else Color(2.4, 1.8, 1.2, 0.9))
	shake(clamp(radius * 0.12, 1.0, 22.0))


func shockwave(pos: Vector2, radius: float, color: Color, time := 0.45) -> void:
	if radius > 220.0:
		_big_shockwave(pos, radius, color, time)
		return
	var s := Sprite2D.new()
	s.texture = _ring_tex
	s.modulate = color
	s.position = pos
	s.scale = Vector2.ONE * 0.1
	world.add_child(s)
	var target := radius / 24.0
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector2.ONE * target, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.queue_free)


## Large rings are drawn as arcs so they stay crisp instead of scaling a tiny texture.
func _big_shockwave(pos: Vector2, radius: float, color: Color, time: float) -> void:
	var n := Node2D.new()
	n.position = pos
	n.modulate = color
	n.set_meta("r", 0.0)
	n.draw.connect(func() -> void:
		var r: float = n.get_meta("r")
		n.draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color.WHITE, 10.0)
		n.draw_arc(Vector2.ZERO, r * 0.93, 0.0, TAU, 96, Color(1, 1, 1, 0.35), 5.0))
	world.add_child(n)
	var tw := n.create_tween().set_parallel(true)
	tw.tween_method(func(r: float) -> void:
		n.set_meta("r", r)
		n.queue_redraw(), 10.0, radius, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "modulate:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(n.queue_free)


func _flash(pos: Vector2, size: float, color: Color, time: float) -> void:
	var s := Sprite2D.new()
	s.texture = _glow_tex
	s.modulate = color
	s.position = pos
	s.scale = Vector2.ONE * size
	world.add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector2.ONE * size * 1.6, time)
	tw.tween_property(s, "modulate:a", 0.0, time)
	tw.chain().tween_callback(s.queue_free)
