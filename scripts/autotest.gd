extends Node
## Debug run:  godot --path . -- --autotest
## Exercises waves, combat, map, shop and planet loss; saves screenshots to user://.

var _main: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = get_parent()
	_run()


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _snap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "user://autotest_%s.png" % tag
	get_viewport().get_texture().get_image().save_png(path)
	print("AUTOTEST saved ", ProjectSettings.globalize_path(path))


func _stats(tag: String) -> void:
	var allies := get_tree().get_nodes_in_group(&"team_ally").size()
	var enemies := get_tree().get_nodes_in_group(&"team_enemy").size()
	var hp := []
	for p in Game.planets:
		hp.append("%s:%d%s" % [p.kind, int(p.hp), "!" if p.threat > 0 else ""])
	print("AUTOTEST [%s] wave=%d allies=%d enemies=%d missiles=%d pickups=%d res=%s planets=%s fps=%d" % [
		tag, Game.director.wave, allies, enemies, get_tree().get_node_count_in_group(&"missiles"),
		get_tree().get_node_count_in_group(&"pickups"), Game.resources, hp, Engine.get_frames_per_second()])


func _run() -> void:
	if "--waves" in OS.get_cmdline_user_args():
		for n in range(1, Game.director.victory_wave + 1):
			var mix := {}
			for k in Game.director._composition(n):
				mix[k] = mix.get(k, 0) + 1
			print("AUTOTEST wave %2d: %s" % [n, mix])
		get_tree().quit()
		return
	if "--carvestress" in OS.get_cmdline_user_args():
		Game.director.next_wave_in = 99999.0
		for round_i in 30:
			for p in Game.planets.duplicate():
				if not is_instance_valid(p) or not p.alive or p.mass_fraction < 0.45:
					continue
				var sz := Vector2(p.image.get_size())
				for k in 6:
					p.carve(sz * 0.5 + Vector2.from_angle(randf() * TAU) * randf() * sz.x * 0.5, randf_range(4.0, 16.0))
			await _wait(0.2)
		print("AUTOTEST carvestress done")
		get_tree().quit()
		return
	if "--planetdeath" in OS.get_cmdline_user_args():
		await _planet_death_test()
		get_tree().quit()
		return
	if "--field" in OS.get_cmdline_user_args():
		await _field_shot()
		get_tree().quit()
		return
	if "--controls" in OS.get_cmdline_user_args():
		await _controls_test()
		get_tree().quit()
		return
	if "--tunnel" in OS.get_cmdline_user_args():
		await _tunnel_test()
		get_tree().quit()
		return
	var player: Player = Game.player
	await _wait(1.5)
	await _snap("0_start")
	_stats("start")

	# Shoot a few rocks for loot, fire a missile salvo.
	Input.action_press("fire")
	Input.action_press("thrust")
	await _wait(1.0)
	Input.action_release("thrust")
	Input.action_press("missile")
	await _wait(0.4)
	Input.action_release("missile")
	await _wait(1.0)
	Input.action_release("fire")

	# Force the first wave right away and jump next to the attacked planet.
	Game.director.next_wave_in = 0.0
	await _wait(0.3)
	var w: Dictionary = Game.director.waves[0]
	var planet: Planet = w.planet
	print("AUTOTEST wave 1 -> ", planet.kind, " ships=", w.ships.size())
	player.teleport(planet.post.global_position + Vector2(0, 60))
	# Let enemies arrive faster.
	for s in w.ships:
		s.global_position = planet.global_position + (s.global_position - planet.global_position).normalized() * (planet.radius + 900.0)
	await _wait(6.0)
	await _snap("1_battle")
	_stats("battle")

	# Heavy gunship + carrier wave at the same planet.
	Game.director.wave = 6
	Game.director.next_wave_in = 0.0
	await _wait(0.3)
	var w2: Dictionary = Game.director.waves[Game.director.waves.size() - 1]
	var p2: Planet = w2.planet
	var kinds := {}
	for s in w2.ships:
		kinds[s.kind] = kinds.get(s.kind, 0) + 1
		s.global_position = p2.global_position + (s.global_position - p2.global_position).normalized() * (p2.radius + 1100.0)
	print("AUTOTEST wave 7 -> ", p2.kind, " mix=", kinds, " active waves=", Game.director.waves.size())
	player.teleport(p2.global_position + (w2.ships[0].global_position - p2.global_position).normalized() * (p2.radius + 500.0))
	await _wait(7.0)
	await _snap("2_heavy_wave")
	_stats("heavy")

	# Map overlay.
	Game.hud.map_view.open()
	await _wait(0.5)
	await _snap("3_map")
	Game.hud.map_view.close()

	# Close-up of an enemy heavy gunship firing its rack, away from turrets.
	var spot := Game.home_planet.global_position + Vector2(0, 2600)
	player.teleport(spot + Vector2(-500, 0))
	player._invulnerable = 60.0
	var hv: AIShip = AIShip.create("heavy", Game.Team.ENEMY)
	hv.position = spot
	hv.rotation = PI
	Game.world.add_child(hv)
	Game.camera.target = null
	Game.camera.global_position = spot + Vector2(-150, 0)
	Game.camera.reset_physics_interpolation()
	await _wait(2.4)
	await _snap("2b_heavy_close")
	await _wait(3.0)
	await _snap("2c_heavy_close")
	hv.die()
	player._invulnerable = 0.0
	Game.camera.target = player

	# Shop at the home post with some resources.
	Game.add_resource("ore", 120)
	Game.add_resource("scrap", 120)
	Game.add_resource("crystal", 6)
	player.teleport(Game.home_planet.post.global_position)
	await _wait(0.3)
	Game.hud.shop.open(Game.home_planet.post)
	await _wait(0.3)
	await _snap("4_shop")
	for b in Game.hud.shop.find_children("*", "Button", true, false):
		if (b as Button).text == "Купить" and not (b as Button).disabled:
			(b as Button).pressed.emit()
			break
	await _wait(0.2)
	print("AUTOTEST upgrades=", Game.upgrades, " res=", Game.resources)
	Game.hud.shop.close_shop()

	# Let the fight run a bit at 3x speed.
	Engine.time_scale = 3.0
	await _wait(20.0)
	Engine.time_scale = 1.0
	_stats("after 60s sim")

	# Destroy an outer planet to check it disappears together with its defenses.
	var victim: Planet = null
	for p in Game.planets:
		if not p.is_home:
			victim = p
			break
	if victim:
		var posts_before := get_tree().get_node_count_in_group(&"posts")
		victim.take_hit(victim.global_position + Vector2(victim.radius, 0), Vector2.LEFT, victim.hp + 1.0, true)
		await _wait(1.5)
		print("AUTOTEST planet lost: planets=", Game.planets.size(), " posts ", posts_before, "->",
				get_tree().get_node_count_in_group(&"posts"))
	await _snap("5_end")
	_stats("end")
	# Losing the home planet ends the game.
	var home := Game.home_planet
	home.take_hit(home.global_position + Vector2(home.radius, 0), Vector2.LEFT, home.hp + 1.0, true)
	await _wait(1.5)
	print("AUTOTEST game_over=", Game.game_over, " paused=", get_tree().paused)
	await _snap("6_gameover")
	get_tree().paused = false
	get_tree().quit()


## Regression: a siege carrier lined up with a tunnel drilled through the planet
## centre must keep hitting the planet instead of firing through the hole forever.
func _tunnel_test() -> void:
	Game.director.next_wave_in = 99999.0
	var planet: Planet = null
	for p in Game.planets:
		if not p.is_home:
			planet = p
			break
	# Drill a straight tunnel through the centre along the X axis.
	var half := Vector2(planet.image.get_size()) * 0.5
	var x := 0.0
	while x < planet.image.get_size().x:
		planet.carve(Vector2(x, half.y), 14.0)
		x += 6.0
	await _wait(0.5)
	var from := planet.global_position + Vector2(planet.radius + 380.0, 0)
	var q := PhysicsRayQueryParameters2D.create(from, planet.global_position, Game.L_PLANETS)
	var hit := get_viewport().world_2d.direct_space_state.intersect_ray(q)
	print("AUTOTEST tunnel: ray to centre hits planet = ", not hit.is_empty())
	var aim := planet.aim_point(from)
	print("AUTOTEST tunnel: aim point offset from centre = ", (aim - planet.global_position).round())

	var carrier := AIShip.create("carrier", Game.Team.ENEMY)
	carrier.objective = planet
	carrier.position = from
	carrier.rotation = PI
	Game.world.add_child(carrier)
	for t in planet.turrets:
		t.obliterate()
	if planet.post:
		planet.post.obliterate()
	Game.player.teleport(planet.global_position + Vector2(0, planet.radius + 900.0))
	Game.camera.target = null
	Game.camera.global_position = planet.global_position + Vector2(200, 0)
	Game.camera.reset_physics_interpolation()
	var hp0 := planet.hp
	Engine.time_scale = 3.0
	await _wait(10.0)
	var hp1 := planet.hp
	await _wait(10.0)
	Engine.time_scale = 1.0
	var hp2 := planet.hp
	print("AUTOTEST tunnel: planet hp %d -> %d -> %d (must keep dropping)" % [hp0, hp1, hp2])
	await _snap("tunnel")
	# Max player zoom-out, camera following the ship at speed.
	Game.camera.target = Game.player
	Game.camera.user_zoom = Game.camera.zoom_min
	Game.player.teleport(planet.global_position + Vector2(-planet.radius - 700.0, 0))
	Input.action_press("turn_right")
	await _wait(1.5)
	Input.action_release("turn_right")
	print("AUTOTEST zoom: ", Game.camera.zoom)
	await _snap("zoom_out")
	Game.camera.user_zoom = 1.0
	Game.camera.target = null

	# Corsairs in action against a defended planet.
	var target: Planet = null
	for p in Game.planets:
		if not p.is_home and p != planet:
			target = p
			break
	var spawned: Array[AIShip] = []
	for i in 5:
		var c := AIShip.create("corsair", Game.Team.ENEMY)
		c.objective = target
		c.position = target.global_position + Vector2(target.radius + 900.0, i * 60.0 - 120.0)
		Game.world.add_child(c)
		spawned.append(c)
	Game.player.teleport(target.global_position + Vector2(0, target.radius + 1200.0))
	Game.player._invulnerable = 999.0
	Game.camera.global_position = target.global_position + Vector2(target.radius + 450.0, 0)
	Game.camera.reset_physics_interpolation()
	await _wait(4.0)
	await _snap("corsairs")
	var alive := spawned.filter(func(c) -> bool: return Game.is_alive(c)).size()
	var turrets_alive := target.turrets.filter(func(t) -> bool: return is_instance_valid(t) and t.alive).size()
	print("AUTOTEST corsairs alive after 4s: %d/5, turrets alive: %d, flies near: %d" % [
		alive, turrets_alive, get_tree().get_nodes_in_group(&"team_ally").size()])
	Engine.time_scale = 3.0
	await _wait(12.0)
	Engine.time_scale = 1.0
	alive = spawned.filter(func(c) -> bool: return Game.is_alive(c)).size()
	turrets_alive = target.turrets.filter(func(t) -> bool: return is_instance_valid(t) and t.alive).size()
	print("AUTOTEST corsairs alive after 40s game time: %d/5, turrets alive: %d, planet hp %d" % [
		alive, turrets_alive, target.hp])
	for c in spawned:
		if Game.is_alive(c):
			var tgt: String = str(c.target.get_class()) + ("/" + c.target.kind if c.target is AIShip or c.target is Turret else "") if c.target else "planet"
			print("AUTOTEST   corsair hull=%d shield=%d dist_to_planet=%d target=%s" % [c.hull, c.shield,
					c.global_position.distance_to(target.global_position) - target.radius, tgt])


## Forward-vector controls: with the nose pointing left, W must fly left,
## D must strafe to the ship's right side, S must push backwards.
func _controls_test() -> void:
	Game.director.next_wave_in = 99999.0
	var pl: Player = Game.player
	pl.teleport(Vector2(0, Game.world_radius * 0.5))
	Game.control_scheme = 0
	# Park the mouse to the left of the ship so the nose points left.
	var vp := get_viewport()
	for step in [["thrust", "W"], ["turn_right", "D"], ["brake", "S"]]:
		pl.velocity = Vector2.ZERO
		vp.warp_mouse(vp.get_visible_rect().size * 0.5 + Vector2(-400, 0))
		await _wait(0.6)
		Input.action_press(step[0])
		await _wait(0.5)
		if step[1] == "W":
			await _snap("controls_forward")
		Input.action_release(step[0])
		var nose := pl.global_transform.x.normalized()
		print("AUTOTEST controls: nose=%s  %s -> velocity dir=%s" % [nose.round(), step[1], pl.velocity.normalized().snapped(Vector2(0.01, 0.01))])


## Screenshots of a meteor field at normal and max zoom-out (readability check).
func _field_shot() -> void:
	Game.director.next_wave_in = 99999.0
	var best: Node2D = null
	var best_n := 0
	for a in get_tree().get_nodes_in_group(&"asteroids"):
		var n := 0
		for b in get_tree().get_nodes_in_group(&"asteroids"):
			if (a as Node2D).global_position.distance_to((b as Node2D).global_position) < 500.0:
				n += 1
		if n > best_n:
			best_n = n
			best = a
		if best_n > 12:
			break
	Game.player.teleport(best.global_position + Vector2(-700, 250))
	Game.camera.target = null
	Game.camera.global_position = best.global_position
	Game.camera.reset_physics_interpolation()
	await _wait(1.0)
	await _snap("field_zoom1")
	Game.camera.user_zoom = Game.camera.zoom_min
	await _wait(1.5)
	await _snap("field_zoomout")


## Carve a planet down bit by bit (hp untouched): it must shatter once the
## remaining mass falls under Planet.DEATH_FRACTION.
func _planet_death_test() -> void:
	Game.director.next_wave_in = 99999.0
	var planet: Planet = null
	for p in Game.planets:
		if not p.is_home:
			planet = p
			break
	var size := Vector2(planet.image.get_size())
	var i := 0
	while is_instance_valid(planet) and planet.alive and i < 400:
		var c := size * 0.5 + Vector2.from_angle(randf() * TAU) * randf() * size.x * 0.45
		planet.carve(c, 14.0)
		i += 1
		if i % 10 == 0:
			await _wait(0.2)   # let the collision rebuild run
			if is_instance_valid(planet):
				print("AUTOTEST carve %d: mass=%.2f integrity=%.2f hp=%d alive=%s" % [
					i, planet.mass_fraction, planet.hp_fraction(), planet.hp, planet.alive])
	print("AUTOTEST planet destroyed=", not is_instance_valid(planet) or not planet.alive,
			" after ", i, " carves; planets left=", Game.planets.size())
