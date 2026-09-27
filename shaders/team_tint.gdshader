shader_type canvas_item;
// Recolours neutral-grey pixels with the team colour (red enemies, blue allies).
// Saturated pixels (cockpits, engines, lights) and the bluish outline keep their colour.

uniform vec4 team_color : source_color = vec4(1.0);

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 c = tex.rgb;
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = (mx - mn) / max(mx, 0.001);
	if (sat < 0.1 && mx > 0.02) {
		vec3 tinted = c * team_color.rgb * 1.7;
		float hi = smoothstep(0.35, 0.9, mx);
		vec3 light = (team_color.rgb * 0.3 + 0.7) * mx * 1.2;
		c = mix(tinted, light, hi);
	}
	COLOR = vec4(c, tex.a) * v_modulate;
}
