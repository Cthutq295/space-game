shader_type canvas_item;
// Makes each star twinkle on its own phase; bright stars peak above 1.0 so the bloom catches them.

uniform float speed = 1.6;
uniform float peak = 1.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// COLOR already holds texture * modulate here.
	vec2 cell = floor(UV / TEXTURE_PIXEL_SIZE / 3.0);
	float h = hash(cell);
	float tw = 0.5 + 0.5 * sin(TIME * speed * (0.4 + h * 1.2) + h * 6.2831);
	COLOR.rgb *= mix(0.55, peak, tw * tw);
}
