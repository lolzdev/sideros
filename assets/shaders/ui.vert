#version 450

layout(location = 0) in vec2 vertPos;
layout(location = 1) in vec4 vertColor;

layout(location = 0) out vec4 fragColor;

layout(push_constant) uniform pc {
    vec2 viewport;
} pushConstants;

void main() {
    vec2 ndc = vec2(
        (vertPos.x / pushConstants.viewport.x) * 2.0 - 1.0,
        (vertPos.y / pushConstants.viewport.y) * 2.0 - 1.0
    );

    fragColor = vertColor;
    gl_Position = vec4(ndc, 0.0, 1.0);
}
