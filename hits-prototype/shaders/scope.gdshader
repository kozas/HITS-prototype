// Telescope eyepiece: a round field of view with a darkened rim; black outside.
shader_type canvas_item;

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float d = length((SCREEN_UV - 0.5) * res);
	float r = 0.47 * min(res.x, res.y);
	float outside = smoothstep(r - 1.5, r + 1.5, d);
	float vignette = smoothstep(r * 0.82, r, d) * 0.65;
	COLOR = vec4(0.0, 0.0, 0.0, max(outside, vignette));
}
