// Grass tufts (Land._grass): vertex coloured, and each tuft grows out of the
// ground as it comes within reach of the camera's focus and sinks back as it
// leaves, so no 64 m patch ever pops in or out at once. Done in the vertex
// shader only: no transparency, light for the web build.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec3 uFocus;
uniform float uNear = 34.0; // full size within this many metres
uniform float uFar = 46.0; // gone beyond this

void vertex() {
	vec3 at = MODEL_MATRIX[3].xyz;
	// a few metres of give per tuft, so the edge is ragged, not a circle
	float jitter = fract(sin(dot(at.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.0 - 3.0;
	float d = length(at.xz - uFocus.xz) + jitter;
	VERTEX *= 1.0 - smoothstep(uNear, uFar, d);
}

void fragment() {
	ALBEDO = albedo.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
}
