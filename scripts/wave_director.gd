class_name WaveDirector
extends Node
## Sends enemy waves at planets. Early on only one planet is attacked at a time;
## from wave `mid_game_wave` on, two waves (two planets) can be active at once, never more.
## The home planet is attacked only late, or when nothing else is left.
## Each wave starts with a short, non-intrusive alarm chime.
## All numbers below are editable on the WaveDirector node in scenes/main.tscn.

signal wave_started(number: int, planet: Planet)

@export var first_wave_delay := 75.0   ## seconds of calm before the first attack
@export var mid_game_wave := 5         ## from this wave two planets may be under attack
@export var home_allowed_wave := 8     ## the home planet can be targeted from this wave
@export var victory_wave := 15         ## survive this many waves to win
@export var engage_distance := 1300.0  ## enemies this close to their planet = "under attack"
@export var budget_base := 4.0         ## wave strength = base + per_wave * wave number
@export var budget_per_wave := 2.3
@export var min_wave_gap := 35.0       ## seconds between waves late in the game
@export var max_wave_gap := 65.0       ## seconds between waves early on

var wave := 0
var next_wave_in := 0.0
var waves: Array[Dictionary] = []   ## {planet: Planet, ships: Array}


func _ready() -> void:
	next_wave_in = first_wave_delay


func _physics_process(delta: float) -> void:
	if Game.game_over:
		return
	_update_waves()
	next_wave_in -= delta
	if next_wave_in <= 0.0:
		var cap := 1 if wave < mid_game_wave - 1 else 2
		if waves.size() < cap and wave < victory_wave:
			launch_wave()
			next_wave_in = max(min_wave_gap, max_wave_gap - wave * 2.5)
		else:
			next_wave_in = 3.0
	if wave >= victory_wave and waves.is_empty():
		Game.end_game(true)


func _update_waves() -> void:
	for p in Game.planets:
		p.threat = 0
	var still: Array[Dictionary] = []
	for w in waves:
		var ships: Array = w.ships.filter(func(s) -> bool: return Game.is_alive(s))
		if ships.is_empty():
			continue
		w.ships = ships
		# If the target planet fell, the wave follows its ships to their new objective.
		if not Game.is_alive(w.planet):
			var s: AIShip = ships[0]
			w.planet = s.objective
		var planet: Planet = w.planet
		if Game.is_alive(planet):
			var level := 1
			var reach := planet.radius + engage_distance
			for s in ships:
				if (s as Node2D).global_position.distance_to(planet.global_position) < reach:
					level = 2
					break
			planet.threat = max(planet.threat, level)
		still.append(w)
	waves = still


func launch_wave() -> void:
	var planet := _pick_planet()
	if planet == null:
		return
	wave += 1
	var dir := planet.global_position.normalized()
	if planet.global_position.length() < 500.0:
		dir = Vector2.from_angle(randf() * TAU)
	var origin := dir.rotated(randf_range(-0.35, 0.35)) * (Game.world_radius - 250.0)

	var ships: Array = []
	for kind in _composition(wave):
		var s := AIShip.create(kind, Game.Team.ENEMY)
		s.objective = planet
		s.position = origin + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 260.0)
		s.rotation = (planet.global_position - s.position).angle()
		Game.world.add_child(s)
		ships.append(s)
		if kind == "carrier":
			for i in 4:
				ships.append(s.spawn_escort())
	Game.explosion(origin, 50.0, Color("ff5a4a"))
	Game.shockwave(origin, 500.0, Color(3.0, 0.8, 0.6, 0.9), 0.8)
	Game.play_sound("alarm", null, -9.0, 1.0, 0.0)
	waves.append({"planet": planet, "ships": ships})
	wave_started.emit(wave, planet)


## Wave mix from a budget (fighter 1, corsair 2, heavy 4, carrier 7 + 4 escort flies).
## Big ships are a fixed few; the rest of the budget is shared out so fighters stay the
## most numerous (squadrons), corsairs are the backbone, heavies/carriers the spice.
##   wave 1: 6 fighters                wave 3: heavy, corsair, ~6 fighters
##   wave 5: carrier, heavy, 2 corsairs, ~5 fighters     wave 15: 2 carriers, ...
func _composition(n: int) -> Array[String]:
	var out: Array[String] = []
	var budget := budget_base + n * budget_per_wave
	var carriers := 0
	if n >= 5:
		carriers = 1 if n < 11 else 2
	for i in carriers:
		out.append("carrier")
		budget -= 7.0
	if n >= 3:
		var heavies := clampi(int(budget * 0.4 / 4.0), 1, 1 + (n - 3) / 4)
		for i in heavies:
			out.append("heavy")
			budget -= 4.0
	if n >= 2:
		var corsairs := maxi(1, roundi(budget * 0.4 / 2.0))
		for i in corsairs:
			out.append("corsair")
			budget -= 2.0
	var fighters := clampi(int(budget), 3, 14)
	for i in fighters:
		out.append("fighter")
	return out


func _pick_planet() -> Planet:
	var targeted: Array = waves.map(func(w: Dictionary) -> Planet: return w.planet)
	var outer: Array[Planet] = []
	var any: Array[Planet] = []
	for p in Game.planets:
		if not Game.is_alive(p) or p in targeted:
			continue
		any.append(p)
		if not p.is_home:
			outer.append(p)
	if not outer.is_empty() and (wave + 1 < home_allowed_wave or randf() < 0.7):
		return outer.pick_random()
	if not any.is_empty():
		return any.pick_random()
	return null


func enemies_alive() -> int:
	var n := 0
	for w in waves:
		n += w.ships.size()
	return n
