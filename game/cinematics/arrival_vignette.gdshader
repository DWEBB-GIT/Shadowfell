shader_type canvas_item;
// One inexpensive overlay: no scene copy, blur, lights or extra 3D pass.
void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(1.05, 1.0);
	float rim = smoothstep(0.22, 0.71, length(p)) * 0.32;
	float lower = smoothstep(0.62, 1.0, UV.y) * 0.18;
	COLOR = vec4(vec3(0.015, 0.012, 0.008), max(rim, lower));
}
