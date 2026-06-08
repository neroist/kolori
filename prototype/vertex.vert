#version 330 core
layout (location = 0) in vec2 aPos;
layout (location = 1) in vec3 aColor;
layout (location = 2) in vec2 aTex;

out vec3 ourColor;
out vec2 pos;
out vec2 TexCoord;
uniform float theta;
uniform float dilation;

void main() {

        mat2 rotation_mat = mat2(
                cos(theta), sin(-theta),
                sin(theta), cos( theta)
        );

        gl_Position = vec4(rotation_mat * aPos, 0, dilation);
        pos = aPos;
        ourColor = aColor;
        TexCoord = aTex * dilation;
}