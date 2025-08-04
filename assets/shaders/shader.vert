#version 450

layout(location = 0) in vec3 vertPos;

layout (binding = 0) uniform ProjUniform {
    mat4 proj;
} proj;

layout (binding = 1) uniform ViewUniform {
    mat4 view;
} view;

void main() {
    vec4 out_vec = proj.proj * view.view * vec4(vertPos, 1.0);
    //vec4 out_vec = proj.proj * vec4(vertPos, 1.0);
    gl_Position = vec4(out_vec.x, out_vec.y, out_vec.z, out_vec.w);
}
