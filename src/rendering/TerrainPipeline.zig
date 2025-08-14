const std = @import("std");
const Mesh = @import("Mesh.zig");
const Camera = @import("Camera.zig");
const vk = @import("vulkan.zig");
const Texture = vk.Texture;
const c = vk.c;
const math = @import("math");
const gltf = @import("gltf.zig");
const Allocator = std.mem.Allocator;
const rendering = @import("rendering.zig");
const lights = rendering.lights;

const max_point_lights = 1024;

layout: c.VkPipelineLayout,
handle: c.VkPipeline,
//vertex_buffer: vk.Buffer,
//index_buffer: vk.Buffer,
texture_set_layout: c.VkDescriptorSetLayout,
descriptor_pool: c.VkDescriptorPool,
descriptor_set: c.VkDescriptorSet,
descriptor_set_layout: c.VkDescriptorSetLayout,
heightmap_sampler: vk.Sampler,
sand_sampler: vk.Sampler,
grass_sampler: vk.Sampler,
rock_sampler: vk.Sampler,
map: c.VkDescriptorSet,

const Self = @This();

pub fn init(
    graphics_pipeline: vk.GraphicsPipeline,
    vertex_shader: c.VkShaderModule,
    fragment_shader: c.VkShaderModule) !Self {

    const device = graphics_pipeline.device;
    const swapchain = graphics_pipeline.swapchain;
    const render_pass = graphics_pipeline.render_pass;

    const vertex_shader_stage_info: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertex_shader,
        .pName = "main",
    };

    const fragment_shader_stage_info: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragment_shader,
        .pName = "main",
    };

    // TODO: shouldn't this be closer to usage?
    const shader_stage_infos: []const c.VkPipelineShaderStageCreateInfo = &.{ vertex_shader_stage_info, fragment_shader_stage_info };

    const vertex_attributes: []const c.VkVertexInputAttributeDescription = Mesh.TerrainVertex.attributeDescriptions();
    const vertex_bindings: []const c.VkVertexInputBindingDescription = &.{Mesh.TerrainVertex.bindingDescription()};

    const vertex_input_info: c.VkPipelineVertexInputStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = vertex_bindings.ptr,
        .vertexAttributeDescriptionCount = 3,
        .pVertexAttributeDescriptions = vertex_attributes.ptr,
    };

    const input_assembly_info: c.VkPipelineInputAssemblyStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    const viewport: c.VkViewport = .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(swapchain.extent.width),
        .height = @floatFromInt(swapchain.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor: c.VkRect2D = .{
        .offset = .{
            .x = 0.0,
            .y = 0.0,
        },
        .extent = swapchain.extent,
    };

    const viewport_state_info: c.VkPipelineViewportStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    const rasterizer_info: c.VkPipelineRasterizationStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
    };

    const multisampling_info: c.VkPipelineMultisampleStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = c.VK_FALSE,
        .rasterizationSamples = device.msaa_samples,
    };

    const color_blend_attachment: c.VkPipelineColorBlendAttachmentState = .{
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = c.VK_TRUE,
        .srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = c.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
    };

    const color_blend_info: c.VkPipelineColorBlendStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        .blendConstants = .{ 0.0, 0.0, 0.0, 0.0 },
    };

    const projection_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
    };

    const view_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
    };

    const directional_light_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 2,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const point_lights_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 5,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const view_pos_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 3,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const heightmap_sampler_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
    };

    const sand_sampler_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const grass_sampler_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 2,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const stone_sampler_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 3,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const bindings = [_]c.VkDescriptorSetLayoutBinding{projection_binding, view_binding, directional_light_binding, point_lights_binding, view_pos_binding};
    const texture_bindings = [_]c.VkDescriptorSetLayoutBinding{heightmap_sampler_binding, sand_sampler_binding, grass_sampler_binding, stone_sampler_binding};

    var descriptor_set_layout: c.VkDescriptorSetLayout = undefined;
    var texture_descriptor_set_layout: c.VkDescriptorSetLayout = undefined;

    const descriptor_set_layout_info = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 5,
        .pBindings = bindings[0..].ptr,
    };

    const texture_descriptor_set_layout_info = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 4,
        .pBindings = texture_bindings[0..].ptr,
    };

    try vk.mapError(c.vkCreateDescriptorSetLayout(device.handle, &descriptor_set_layout_info, null, &descriptor_set_layout));
    try vk.mapError(c.vkCreateDescriptorSetLayout(device.handle, &texture_descriptor_set_layout_info, null, &texture_descriptor_set_layout));

    var set_layouts = [_]c.VkDescriptorSetLayout{descriptor_set_layout, texture_descriptor_set_layout};

    const lights_range: c.VkPushConstantRange = .{
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .offset = 0,
        .size = 4,
    };

    const range: [1]c.VkPushConstantRange = .{lights_range};

    const layout_info: c.VkPipelineLayoutCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 2,
        .pSetLayouts = set_layouts[0..].ptr,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = range[0..].ptr,
    };

    var layout: c.VkPipelineLayout = undefined;

    try vk.mapError(c.vkCreatePipelineLayout(device.handle, &layout_info, null, @ptrCast(&layout)));

    const depth_stencil: c.VkPipelineDepthStencilStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = c.VK_TRUE,
        .depthWriteEnable = c.VK_TRUE,
        .depthCompareOp = c.VK_COMPARE_OP_LESS,
        .depthBoundsTestEnable = c.VK_FALSE,
        .minDepthBounds = 0.0,
        .maxDepthBounds = 1.0,
        .stencilTestEnable = c.VK_FALSE,
    };

    const pipeline_info: c.VkGraphicsPipelineCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = shader_stage_infos.ptr,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly_info,
        .pViewportState = &viewport_state_info,
        .pRasterizationState = &rasterizer_info,
        .pMultisampleState = &multisampling_info,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &color_blend_info,
        .pDynamicState = null,
        .layout = layout,
        .renderPass = render_pass.handle,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    var pipeline: c.VkPipeline = undefined;

    try vk.mapError(c.vkCreateGraphicsPipelines(device.handle, null, 1, &pipeline_info, null, @ptrCast(&pipeline)));

    const size = c.VkDescriptorPoolSize{
        .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 5,
    };

    const sampler_size = c.VkDescriptorPoolSize{
        .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 4,
    };

    const sizes = [_]c.VkDescriptorPoolSize {size, sampler_size};

    const descriptor_pool_info = c.VkDescriptorPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 2,
        .poolSizeCount = 2,
        .pPoolSizes = sizes[0..].ptr,
    };

    var descriptor_pool: c.VkDescriptorPool = undefined;

    try vk.mapError(c.vkCreateDescriptorPool(device.handle, &descriptor_pool_info, null, &descriptor_pool));

    const descriptor_allocate_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = set_layouts[0..].ptr,
    };

    var descriptor_set: c.VkDescriptorSet = undefined;

    try vk.mapError(c.vkAllocateDescriptorSets(device.handle, &descriptor_allocate_info, &descriptor_set));

    const descriptor_buffer_info = c.VkDescriptorBufferInfo{
        .buffer = graphics_pipeline.projection_buffer.handle,
        .offset = 0,
        .range = graphics_pipeline.projection_buffer.size,
    };

    const write_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 0,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .pBufferInfo = &descriptor_buffer_info,
    };

    c.vkUpdateDescriptorSets(device.handle, 1, &write_descriptor_set, 0, null);

    const view_descriptor_buffer_info = c.VkDescriptorBufferInfo{
        .buffer = graphics_pipeline.view_buffer.handle,
        .offset = 0,
        .range = graphics_pipeline.view_buffer.size,
    };

    const write_view_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 1,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .pBufferInfo = &view_descriptor_buffer_info,
    };

    c.vkUpdateDescriptorSets(device.handle, 1, &write_view_descriptor_set, 0, null);

    const directional_light_descriptor_buffer_info = c.VkDescriptorBufferInfo{
        .buffer = graphics_pipeline.directional_light_buffer.handle,
        .offset = 0,
        .range = graphics_pipeline.directional_light_buffer.size,
    };

    const write_directional_light_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 2,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .pBufferInfo = &directional_light_descriptor_buffer_info,
    };

    c.vkUpdateDescriptorSets(device.handle, 1, &write_directional_light_descriptor_set, 0, null);

    var point_lights_descriptor_buffer_info: c.VkDescriptorBufferInfo = undefined;
    point_lights_descriptor_buffer_info.buffer = graphics_pipeline.point_lights_buffer.handle;
    point_lights_descriptor_buffer_info.offset = 0;
    point_lights_descriptor_buffer_info.range = @sizeOf(lights.PointLight) * max_point_lights;

    const write_point_lights_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 5,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .pBufferInfo = @ptrCast(&point_lights_descriptor_buffer_info),
    };

    c.vkUpdateDescriptorSets(device.handle, 1, &write_point_lights_descriptor_set, 0, null);

    const view_pos_descriptor_buffer_info = c.VkDescriptorBufferInfo{
        .buffer = graphics_pipeline.view_pos_buffer.handle,
        .offset = 0,
        .range = graphics_pipeline.view_pos_buffer.size,
    };

    const write_view_pos_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 3,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .pBufferInfo = &view_pos_descriptor_buffer_info,
    };

    c.vkUpdateDescriptorSets(device.handle, 1, &write_view_pos_descriptor_set, 0, null);

    return .{
        .layout = layout,
        .handle = pipeline,
        .texture_set_layout = texture_descriptor_set_layout,
        .descriptor_pool = descriptor_pool,
        .descriptor_set = descriptor_set,
        .descriptor_set_layout = descriptor_set_layout,
        .heightmap_sampler = try vk.Sampler.init(device, .nearest),
        .sand_sampler = try vk.Sampler.init(device, .linear),
        .grass_sampler = try vk.Sampler.init(device, .linear),
        .rock_sampler = try vk.Sampler.init(device, .linear),
        .map = undefined,
    };
}

pub fn setMaps(self: *Self, device: anytype, heightmap: Texture) !void {
    var set_layouts = [_]c.VkDescriptorSetLayout{self.texture_set_layout};
    const descriptor_allocate_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = self.descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = set_layouts[0..].ptr,
    };

    var descriptor_set: c.VkDescriptorSet = undefined;
    try vk.mapError(c.vkAllocateDescriptorSets(device.handle, &descriptor_allocate_info, &descriptor_set));

    const height_info: c.VkDescriptorImageInfo = .{
        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = heightmap.image_view,
        .sampler = self.heightmap_sampler.handle,
    };

    const sand = try Texture.init("assets/textures/sand.png", device);
    const grass = try Texture.init("assets/textures/grass.png", device);
    const rock = try Texture.init("assets/textures/rock.png", device);

    const sand_info: c.VkDescriptorImageInfo = .{
        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = sand.image_view,
        .sampler = self.sand_sampler.handle,
    };

    const grass_info: c.VkDescriptorImageInfo = .{
        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = grass.image_view,
        .sampler = self.grass_sampler.handle,
    };

    const rock_info: c.VkDescriptorImageInfo = .{
        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = rock.image_view,
        .sampler = self.rock_sampler.handle,
    };

    const write_height_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 0,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &height_info,
    };

    const write_sand_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 1,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &sand_info,
    };

    const write_grass_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 2,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &grass_info,
    };

    const write_rock_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 3,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &rock_info,
    };

    const writes = [_]c.VkWriteDescriptorSet {write_height_descriptor_set, write_sand_descriptor_set, write_grass_descriptor_set, write_rock_descriptor_set};

    c.vkUpdateDescriptorSets(device.handle, 4, writes[0..].ptr, 0, null);

    self.map = descriptor_set;
}

pub fn bind(self: Self, device: vk.Device, frame: usize) void {
    std.debug.assert(frame < 2);
    c.vkCmdBindPipeline(device.command_buffers[frame], c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.handle);
}

pub fn deinit(self: Self, device: vk.Device) void {
    self.textures.deinit();
    self.diffuse_sampler.deinit(device);
    self.specular_sampler.deinit(device);
    self.projection_buffer.deinit(device.handle);
    c.vkDestroyDescriptorSetLayout(device.handle, self.descriptor_set_layout, null);
    c.vkDestroyDescriptorPool(device.handle, self.descriptor_pool, null);
    c.vkDestroyPipeline(device.handle, self.handle, null);
    c.vkDestroyPipelineLayout(device.handle, self.layout, null);
}
