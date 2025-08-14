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

layout (set = 1, binding = 0) uniform sampler2D diffuseSampler;

void main() {
    float texelSize = 1.0 / (50*4);
    float hL = texture(diffuseSampler, uv - vec2(texelSize, 0.0)).r * 10;
    float hR = texture(diffuseSampler, uv + vec2(texelSize, 0.0)).r * 10;
    float hD = texture(diffuseSampler, uv - vec2(0.0, texelSize)).r * 10;
    float hU = texture(diffuseSampler, uv + vec2(0.0, texelSize)).r * 10;

    float dX = (hR - hL) * 15.0;
    float dY = (hU - hD) * 15.0;

    float y = texture(diffuseSampler, uv).x;
    
    vec4 out_vec = proj.proj * view.view * vec4(vec3(vertPos.x, y * 10, vertPos.z), 1.0);
    FragPos = vec3(vertPos.x, y, vertPos.z);

    Normal = normalize(vec3(-dX, -dY, 1.0));
    TexCoords = uv;
    gl_Position = out_vec;
}
