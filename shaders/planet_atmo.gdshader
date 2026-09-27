shader_type canvas_item;
// Atmosphere glow built from the planet's *current* (deformed) pixel mask, so the
// halo follows craters, tunnels and halves instead of the original perfect circle.
// Drawn on a quad padded by `pad` texels around the planet texture; glow fades
// with distance to the nearest remaining planet pixel, quantised with a Bayer
// dither to match the pixel-art look.

uniform sampler2D planet_tex : filter_nearest;
uniform vec2 planet_size = vec2(240.0);   // planet texture size, texels
uniform float pad = 18.0;                 // glow reach, texels
uniform vec4 glow_color : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform float strength = 0.42;

const int DIRS = 16;
const int STEPS = 6;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[x + y * 4]) + 0.5) / 16.0;
}

float mass_at(vec2 texel) {
	vec2 uv = texel / planet_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return step(0.5, texture(planet_tex, uv).a);
}

void fragment() {
	vec2 full = planet_size + 2.0 * pad;
	vec2 cell = floor(UV * full);
	vec2 texel = cell - pad + 0.5;
	float g = 0.0;
	if (mass_at(texel) < 0.5) {
		for (int s = 1; s <= STEPS; s++) {
			float dist = pad * float(s) / float(STEPS);
			float hit = 0.0;
			for (int i = 0; i < DIRS; i++) {
				float a = float(i) * 6.2831853 / float(DIRS) + float(s) * 0.37;
				hit = max(hit, mass_at(texel + vec2(cos(a), sin(a)) * dist));
			}
			if (hit > 0.0) {
				g = 1.0 - (dist - pad / float(STEPS)) / pad;
				break;
			}
		}
	}
	g = pow(clamp(g, 0.0, 1.0), 2.2);
	float lv = floor(g * 4.0 + bayer4(cell)) / 4.0;
	COLOR = vec4(glow_color.rgb, lv * strength) * COLOR;
}
