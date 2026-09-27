class_name Arsenal
## The player's weapons by upgrade level (bought in the station shop).
## Enemy, ally and turret guns are Weapon nodes inside their scenes
## (scenes/ships/*.tscn, scenes/world/turret_*.tscn) - edit them in the Inspector.


# ------------------------------------------------------------------ player
static func player_blaster(level: int) -> Weapon:
	var w := Weapon.new()
	w.kind = Weapon.Kind.BOLT
	w.interval = [0.13, 0.115, 0.105, 0.095, 0.085][level]
	w.damage = [8.0, 10.0, 11.0, 12.0, 13.0][level]
	w.count = [1, 1, 2, 2, 3][level]
	w.spread = [0.0, 0.0, 0.05, 0.05, 0.1][level]
	w.speed = 1150.0
	w.life = 1.3
	w.muzzles = [Vector2(22, -9), Vector2(22, 9)]
	w.inherit_velocity = 0.6
	w.sound_db = -10.0
	return w


static func player_missiles(level: int) -> Weapon:
	var w := Weapon.new()
	w.kind = Weapon.Kind.MISSILE
	w.salvo = true
	w.magazine = [2, 3, 4, 6, 8][level]
	w.reload_time = [3.2, 3.0, 2.8, 2.6, 2.4][level]
	w.interval = 0.14
	w.damage = 22.0
	w.blast_radius = 55.0
	w.speed = 700.0
	w.missile_accel = 1400.0
	w.missile_turn = 4.5
	w.missile_life = 4.5
	w.muzzles = [Vector2(-4, -16), Vector2(-4, 16)]
	w.sound = "missile"
	w.sound_db = -8.0
	return w


static func player_plasma() -> Weapon:
	var w := Weapon.new()
	w.kind = Weapon.Kind.PLASMA
	w.interval = 1.1
	w.damage = 45.0
	w.blast_radius = 120.0
	w.speed = 650.0
	w.life = 1.8
	w.muzzles = [Vector2(24, 0)]
	w.sound = "plasma"
	w.sound_db = -3.0
	return w
