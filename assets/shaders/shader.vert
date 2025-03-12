#version 450

layout(location = 0) in vec3 vertPos;

layout(binding = 0) uniform UniformObject {
    mat4 proj;
    mat4 view;
    mat4 model;
} ubo;

void main() {
    gl_Position = ubo.view * ubo.proj * vec4(vertPos, 1.0);
}
