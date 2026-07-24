shader_type spatial;
render_mode unshaded, cull_front;

uniform float outline_width = 0.05;
uniform vec4 outline_color : hint_color;

void vertex() {
    // Extrude along the vertex normal so the back faces (cull_front) form a rim.
    vec3 normal = normalize(NORMAL);
    VERTEX += normal * outline_width;
}

void fragment() {
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a;
}