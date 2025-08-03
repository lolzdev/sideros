#version 450

layout(location = 0) in vec3 vertPos;

layout (binding = 0) uniform Uniform {
    mat4 proj;
} ubo;

void main() {
    vec4 out_vec = ubo.proj * vec4(vertPos, 1.0);
    gl_Position = vec4(out_vec.x, out_vec.y, 0.5, out_vec.w);
}
