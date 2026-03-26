shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float pixel_size = 4.0;

void fragment() {
    vec2 screen_size = vec2(textureSize(screen_texture, 0));
    vec2 uv = floor(SCREEN_UV * screen_size / pixel_size) * pixel_size / screen_size;
    COLOR = texture(screen_texture, uv);
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
