pub const DirectionalLight = extern struct {
    direction: [3]f32 align(16),
    ambient: [3]f32 align(16),
    diffuse: [3]f32 align(16),
    specular: [3]f32 align(16),
};

pub const PointLight = extern struct {
    position: [3]f32 align(16),
    ambient: [3]f32 align(16),
    diffuse: [3]f32 align(16),
    specular: [3]f32 align(16),
    data: [3]f32 align(16),
};
