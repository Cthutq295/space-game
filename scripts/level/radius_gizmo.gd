@tool
class_name RadiusGizmo
extends Node2D
## Editor-only circle (e.g. a post's shop aura or a turret's range). Invisible in game.
## With `radius_property` set, the radius follows that property of the parent node
## (e.g. "attack_range"), so the circle updates as you edit the value in the Inspector.

@export var radius := 200.0:
	set(v):
		radius = v
		queue_redraw()
@export var radius_property := ""
@export var color := Color(0.4, 0.8, 1.0, 0.5):
	set(v):
		color = v
		queue_redraw()


func _ready() -> void:
	set_process(Engine.is_editor_hint())


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, color, 2.0)


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or radius_property == "" or get_parent() == null:
		return
	var v = get_parent().get(radius_property)
	if v is float and not is_equal_approx(v, radius):
		radius = v
