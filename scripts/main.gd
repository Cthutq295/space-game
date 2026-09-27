extends Node2D
## Game shell (scenes/main.tscn): bloom environment, parallax background, the
## World (player + the level + everything spawned at runtime), camera, wave
## director and HUD. The level itself is a separate scene - pick it in
## `level_scene` and edit it in scenes/levels/.

@export var level_scene: PackedScene

@onready var world: Node2D = $World
@onready var player: Player = $World/Player
@onready var camera: GameCamera = $Camera
@onready var director: WaveDirector = $WaveDirector


func _enter_tree() -> void:
	# Before any child is ready: fresh score, upgrades and registries.
	Game.reset()


func _ready() -> void:
	randomize()
	Game.world = world
	Game.director = director
	Game.camera = camera

	var level := level_scene.instantiate()
	world.add_child(level)   # Level._ready: sector size, player spawn, links posts/turrets to planets
	if Game.home_planet:
		Game.home_planet.lost.connect(func(_p: Planet) -> void: Game.end_game(false))

	player.teleport(Game.player_spawn)
	player.rotation = -PI / 2.0
	camera.target = player
	camera.make_current()
	camera.snap_to_target()

	Input.set_custom_mouse_cursor(preload("res://assets/sprites/crosshair.png"), Input.CURSOR_ARROW, Vector2(12, 12))
	Game.start_music()

	if "--autotest" in OS.get_cmdline_user_args():
		var t: Node = load("res://scripts/autotest.gd").new()
		add_child(t)


func _exit_tree() -> void:
	Asteroid.clear_cache()
	AIShip.clear_cache()
