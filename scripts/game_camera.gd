class_name GameCamera
extends Camera2D
## Smoothly follows the target with a slight delay, looks ahead in the direction
## of motion, zooms out a little at high speed and supports screen shake.
## The player can zoom with the mouse wheel (or +/-): down to 2x farther out.
## Runs in the physics step; physics interpolation smooths it on high-Hz screens.

@export var follow_speed := 3.2      ## Higher = tighter follow (less delay).
@export var look_ahead := 0.32       ## Seconds of velocity to lead the camera by.
@export var max_look_ahead := 280.0  ## At zoom 1; grows when zoomed out.
@export var zoom_min := 0.5          ## Farthest the player can zoom out (2x view).
@export var zoom_max := 1.25
@export var zoom_step := 1.15
@export var speed_zoom_out := 0.85   ## Extra zoom factor at max speed.

var target: Ship
var user_zoom := 1.0

var _smooth_user_zoom := 1.0
var _speed_factor := 1.0
var _shake := 0.0


func _init() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _unhandled_input(event: InputEvent) -> void:
	if Game.map_open:
		return
	if event.is_action_pressed("zoom_in"):
		user_zoom = clampf(user_zoom * zoom_step, zoom_min, zoom_max)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("zoom_out"):
		user_zoom = clampf(user_zoom / zoom_step, zoom_min, zoom_max)
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_smooth_user_zoom = lerpf(_smooth_user_zoom, user_zoom, 1.0 - exp(-8.0 * delta))
	if target and is_instance_valid(target):
		var vel := target.velocity
		# Zoomed out = see farther, so lead farther ahead too.
		var lead := (vel * look_ahead).limit_length(max_look_ahead / zoom.x)
		var desired := target.global_position + lead
		global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
		var t: float = clamp(vel.length() / target.max_speed, 0.0, 1.0)
		_speed_factor = lerpf(_speed_factor, lerpf(1.0, speed_zoom_out, t * t), 1.0 - exp(-1.2 * delta))
	var z := _smooth_user_zoom * _speed_factor
	zoom = Vector2(z, z)

	_shake = max(_shake - delta * (_shake * 5.0 + 3.0), 0.0)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake


func add_shake(amount: float) -> void:
	_shake = min(_shake + amount, 28.0)


func snap_to_target() -> void:
	if target:
		global_position = target.global_position
		reset_physics_interpolation()
