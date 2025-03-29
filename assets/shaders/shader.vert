#version 450

layout(location = 0) in vec3 vertPos;

layout (binding = 0) uniform Uniform {
    mat4 proj;
} ubo;

void main() {
    gl_Position = ubo.proj * vec4(vertPos, 1.0);
}
