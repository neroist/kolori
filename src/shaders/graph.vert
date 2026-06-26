#version 300 es

precision highp float;
precision highp int;
precision highp sampler2D;

layout (location = 0) in vec2 in_pos;

out vec2 tex_aspect_ratio;

uniform sampler2D tex;

void main()
{
    gl_Position = vec4(in_pos, 0, 1);
    
	vec2 size = vec2(textureSize(tex, 0));
    tex_aspect_ratio = vec2(1., size.x / size.y);
	if (size.x < size.y) {
		tex_aspect_ratio = 1. / tex_aspect_ratio.yx;
	}
}