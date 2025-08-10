#version 450

#define MAX_POINT_LIGHTS 1024

struct PointLight {
	vec3 position;
	vec3 ambient;
	vec3 diffuse;
	vec3 specular;
	vec3 data;
};

layout(location = 0) out vec4 outColor;

layout(location = 2) in vec3 Normal;
layout(location = 3) in vec3 FragPos;
layout(location = 4) in vec2 TexCoords;

layout (binding = 2) uniform DirectionalLight {
	vec3 direction;

	vec3 ambient;
	vec3 diffuse;
	vec3 specular;
} directional_light;
layout (binding = 5) uniform PointLights {    
	PointLight point_lights[MAX_POINT_LIGHTS];
} point_lights;

layout (binding = 3) uniform ViewUniform {
    vec3 pos;
} viewPos;

layout(push_constant) uniform pc {
    int light_count;
} pushConstants;

layout (set = 1, binding = 0) uniform sampler2D diffuseSampler;
layout (set = 1, binding = 1) uniform sampler2D specularSampler;

vec3 calc_directional_light(vec3 normal, vec3 viewDir) {
	vec3 lightDir = normalize(-directional_light.direction);
	float diff = max(dot(normal, lightDir), 0.0);
	vec3 reflectDir = reflect(-lightDir, normal);
	float spec = pow(max(dot(viewDir, reflectDir), 0.0), 2);
	vec3 ambient  = directional_light.ambient  * vec3(texture(diffuseSampler, TexCoords));
	vec3 diffuse  = directional_light.diffuse  * diff * vec3(texture(diffuseSampler , TexCoords));
	vec3 specular = directional_light.specular * spec * vec3(texture(specularSampler, TexCoords));
	return (ambient + diffuse + specular);
}

vec3 calc_point_light(int index, vec3 normal, vec3 fragPos, vec3 viewDir) {
	float constant = point_lights.point_lights[index].data[0];
	float linear = point_lights.point_lights[index].data[1];
	float quadratic = point_lights.point_lights[index].data[2];

	vec3 lightDir = normalize(point_lights.point_lights[index].position - fragPos);
	float diff = max(dot(normal, lightDir), 0.0);
	vec3 reflectDir = reflect(-lightDir, normal);
	float spec = pow(max(dot(viewDir, reflectDir), 0.0), 2);
	float distance    = length(point_lights.point_lights[index].position - fragPos);
	float attenuation = 1.0 / (constant + linear * distance + quadratic * (distance * distance));
	vec3 ambient  = point_lights.point_lights[index].ambient  * vec3(texture(diffuseSampler, TexCoords));
	vec3 diffuse  = point_lights.point_lights[index].diffuse  * diff * vec3(texture(diffuseSampler, TexCoords));
	vec3 specular = point_lights.point_lights[index].specular * spec * vec3(texture(specularSampler, TexCoords));
	ambient  *= attenuation;
	diffuse  *= attenuation;
	specular *= attenuation;
	return (ambient + diffuse + specular);
}

void main() {
	vec3 norm = normalize(Normal);
	vec3 viewDir = normalize(viewPos.pos - FragPos);

	vec3 result = calc_directional_light(norm, viewDir);
	//vec3 result = vec3(0.0, 0.0, 0.0);
	for(int i = 0; i < pushConstants.light_count; i++)
		result += calc_point_light(i, norm, FragPos, viewDir);    

	outColor = vec4(result, 1.0);	
}
