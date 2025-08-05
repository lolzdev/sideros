#version 450

layout(location = 0) in vec3 vertPos;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;

layout (binding = 0) uniform ProjUniform {
    mat4 proj;
} proj;

layout (binding = 1) uniform ViewUniform {
    mat4 view;
} view;

layout(location = 2) out vec3 Normal;
layout(location = 3) out vec3 FragPos;
layout(location = 4) out vec2 TexCoords;

void main() {
    vec4 out_vec = proj.proj * view.view * vec4(vertPos, 1.0);
    //vec4 out_vec = proj.proj * vec4(vertPos, 1.0);
    FragPos = vec3(vec4(vertPos, 1.0));
    Normal = normal;
    TexCoords = uv;
    gl_Position = vec4(out_vec.x, out_vec.y, out_vec.z, out_vec.w);
}
