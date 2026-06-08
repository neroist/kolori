#version 330 core
layout (location = 0) in vec2 _pos;
// layout (location = 1) in vec2 tex_coords;

out vec2 pos;

void main()
{
    gl_Position = vec4(_pos, 0, 1);
    pos = _pos;
}