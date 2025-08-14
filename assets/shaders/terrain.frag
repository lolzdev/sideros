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

in vec4 gl_FragCoord;

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

layout (set = 1, binding = 1) uniform sampler2D sand;
layout (set = 1, binding = 2) uniform sampler2D grass;
layout (set = 1, binding = 3) uniform sampler2D rock;

vec3 calc_directional_light(vec3 normal, vec3 viewDir, vec3 diffuse) {
	vec3 lightDir = normalize(-directional_light.direction);
	float diff = max(dot(normal, lightDir), 0.0);
	vec3 ambient = directional_light.ambient * diffuse;
	vec3 d  = directional_light.diffuse  * diff * diffuse;
	return (ambient + d);
}

vec3 calc_point_light(int index, vec3 normal, vec3 fragPos, vec3 viewDir, vec3 diffuse) {
	float constant = point_lights.point_lights[index].data[0];
	float linear = point_lights.point_lights[index].data[1];
	float quadratic = point_lights.point_lights[index].data[2];

	vec3 lightDir = normalize(point_lights.point_lights[index].position - fragPos);
	float diff = max(dot(normal, lightDir), 0.0);
	vec3 reflectDir = reflect(-lightDir, normal);
	float distance    = length(point_lights.point_lights[index].position - fragPos);
	float attenuation = 1.0 / (constant + linear * distance + quadratic * (distance * distance));
	vec3 ambient  = point_lights.point_lights[index].ambient * diffuse;
	vec3 d  = point_lights.point_lights[index].diffuse  * diff * diffuse;
	ambient  *= attenuation;
	d  *= attenuation;
	return (ambient + d);
}

void main() {
	vec3 norm = normalize(Normal);
	vec3 viewDir = normalize(viewPos.pos - FragPos);

	    

	float height = FragPos.y;
	
	float sandWeight = 1.0 - smoothstep(0.0, 0.035, height);
	float grassWeight = smoothstep(0.035, 0.15, height) - smoothstep(0.25, 0.4, height);
	float rockWeight = smoothstep(0.25, 0.4, height);

	float total = sandWeight + grassWeight + rockWeight;
	sandWeight /= total;
	grassWeight /= total;
	rockWeight /= total;

	vec4 sandColor = texture(sand, TexCoords);
	vec4 grassColor = texture(grass, TexCoords);
	vec4 rockColor = texture(rock, TexCoords);

	vec4 finalColor = sandColor * sandWeight + 
			 grassColor * grassWeight + 
			 rockColor * rockWeight;
	
	vec3 result = calc_directional_light(norm, viewDir, vec3(finalColor));
	//vec3 result = vec3(0.0, 0.0, 0.0);
	for(int i = 0; i < pushConstants.light_count; i++)
		result += calc_point_light(i, norm, FragPos, viewDir, vec3(finalColor));

	outColor = vec4(result, 1.0);
	//outColor = vec4(finalColor);
}
