#version 330 core

in vec3 ourColor;
in vec2 pos;
in vec2 TexCoord;
out vec4 FragColor;

uniform float theta;
uniform sampler2D tex;

const float PI = 3.141591f;
const float TWO_OVER_PI = 2.0f / PI;

vec3 hsl2rgb(vec3 hsl) {
    vec3 rgb = clamp(abs(mod(hsl.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return hsl.z + hsl.y * (rgb - 0.5) * (1.0 - abs(2.0 * hsl.z - 1.0));
}

vec3 domain_color(in vec2 z, float k){
    float angle = atan(z.y,z.x);
    float hue = (angle/(2.0 * PI));
    float light = TWO_OVER_PI * atan(pow(length(z),k));
    return vec3(hue,1.0f,light);
}

vec2 convert_coordinates(in vec2 pos, in vec2 resolution, in float range){
    return range * (pos - 0.5f * resolution)/resolution.y;
}

vec2 cmul(in vec2 a, in vec2 b) {
    return vec2(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

vec2 cexp(in vec2 a) {
    return vec2(cos(a.x), sin(a.y));
}

vec2 cln(in vec2 a) {
    return vec2(length(a), atan(a.x, a.y));
}

void main() {
    // FragColor = vec4(hsl2rgb(domain_color(pos, 0.55)), 1);
    FragColor = vec4(texture(tex, cexp(cmul(cln(pos), (vec2(0, 1))))).xyz, 1);
}
