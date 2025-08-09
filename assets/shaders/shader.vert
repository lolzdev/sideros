#version 450

struct Transform {
	mat4 translation;
	mat4 scale;
	mat4 rotation;
	vec4 quaternion;
};

layout(location = 0) in vec3 vertPos;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;

layout (binding = 0) uniform ProjUniform {
    mat4 proj;
} proj;

layout (binding = 1) uniform ViewUniform {
    mat4 view;
} view;

layout (binding = 4) readonly buffer TransformUniform {
    Transform transforms[];
} transform;

layout(location = 2) out vec3 Normal;
layout(location = 3) out vec3 FragPos;
layout(location = 4) out vec2 TexCoords;

layout(push_constant) uniform pc {
    layout(offset = 4) int transform_index;
} pushConstants;

void main() {
    int transform_index = pushConstants.transform_index;
    mat4 transformation = transform.transforms[transform_index].translation * transform.transforms[transform_index].scale * transform.transforms[transform_index].rotation;
    vec4 out_vec = proj.proj * view.view * transformation * vec4(vertPos, 1.0);
    FragPos = vec3(transformation * vec4(vertPos, 1.0));

    Normal = mat3(transpose(inverse(transformation))) * normal;
    TexCoords = uv;
    gl_Position = out_vec;
}
