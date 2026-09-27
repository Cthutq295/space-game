class_name Explosives
## Shared area-damage helper for plasma, shells and missiles.


## Damages everything hostile to `team` within `radius` (except `skip`), with falloff.
## Planets are not affected by area damage; only direct hits carve them.
static func blast(world: World2D, point: Vector2, radius: float, dmg: float, team: int, skip: Object = null) -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, point)
	q.collision_mask = Game.hostile_mask(team) & ~Game.L_PLANETS
	q.collide_with_areas = true
	for r in world.direct_space_state.intersect_shape(q, 48):
		var c: Object = r.collider
		if c == skip or not is_instance_valid(c) or not c.has_method("take_hit"):
			continue
		var n := c as Node2D
		var away := n.global_position - point
		var falloff: float = clamp(1.0 - away.length() / (radius * 1.3), 0.3, 1.0)
		var dir := away.normalized() if away != Vector2.ZERO else Vector2.RIGHT
		c.take_hit(n.global_position - dir * 6.0, dir, dmg * falloff, false)
