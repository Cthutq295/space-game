shader_type canvas_item;
// Flat-colour silhouette of the sprite. Placed slightly enlarged behind a meteor
// it becomes a thin rim that keeps small rocks readable against the background.
// Values above 1.0 in `tint` make the rim catch the bloom (used for crystals).

uniform vec4 tint = vec4(1.0);

void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(tint.rgb, a * tint.a);
}
