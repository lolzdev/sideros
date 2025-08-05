#version 450

layout(location = 0) out vec4 outColor;

layout(location = 2) in vec3 Normal;
layout(location = 3) in vec3 FragPos;
layout(location = 4) in vec2 TexCoords;

layout (binding = 2) uniform LightUniform {
    vec3 pos;
} lightPos;

layout (binding = 3) uniform ViewUniform {
    vec3 pos;
} viewPos;

layout (set = 1, binding = 0) uniform sampler2D textureSampler;
layout (set = 1, binding = 1) uniform sampler2D diffuseSampler;

void main() {
	vec3 lightDiffuse = vec3(0.5, 0.5, 0.5);
	vec3 lightAmbient = vec3(0.2, 0.2, 0.2);
	vec3 lightSpecular = vec3(1.0, 1.0, 1.0);

	vec3 norm = normalize(Normal);
	vec3 lightDir = normalize(lightPos.pos - FragPos);
	float diff = max(dot(norm, lightDir), 0.0);
	vec3 diffuse = lightDiffuse * diff * vec3(texture(textureSampler, TexCoords));
	vec3 ambient = lightAmbient * vec3(texture(textureSampler, TexCoords));

	vec3 viewDir = normalize(viewPos.pos - FragPos);
	vec3 reflectDir = reflect(-lightDir, norm);
	float spec = pow(max(dot(viewDir, reflectDir), 0.0), 2);
	vec3 specular = lightSpecular * spec * vec3(texture(diffuseSampler, TexCoords));

	vec3 result = (ambient + diffuse + specular);
	outColor = vec4(result, 1.0);
}
