const std = @import("std");
const Mesh = @import("Mesh.zig");
const Camera = @import("Camera.zig");
const vk = @import("vulkan.zig");
const Texture = vk.Texture;
const c = vk.c;
const math = @import("math");

layout: c.VkPipelineLayout,
handle: c.VkPipeline,
texture_set_layout: c.VkDescriptorSetLayout,
descriptor_pool: c.VkDescriptorPool,
descriptor_set: c.VkDescriptorSet,
descriptor_set_layout: c.VkDescriptorSetLayout,
projection_buffer: vk.Buffer,
light_buffer: vk.Buffer,
view_buffer: vk.Buffer,
view_memory: [*c]u8,
transform_memory: [*c]u8,
view_pos_memory: [*c]u8,
texture_sampler: vk.Sampler,
diffuse_sampler: vk.Sampler,
textures: std.ArrayList(c.VkDescriptorSet),
light_pos: [*]f32,

const Self = @This();

pub fn init(allocator: std.mem.Allocator, device: vk.Device, swapchain: vk.Swapchain, render_pass: vk.RenderPass, vertex_shader: c.VkShaderModule, fragment_shader: c.VkShaderModule) !Self {
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

    const vertex_attributes: []const c.VkVertexInputAttributeDescription = Mesh.Vertex.attributeDescriptions();
    const vertex_bindings: []const c.VkVertexInputBindingDescription = &.{Mesh.Vertex.bindingDescription()};

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
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
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

    const transform_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 4,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
    };

    const light_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 2,
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

    const texture_sampler_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const diffuse_sampler_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const bindings = [_]c.VkDescriptorSetLayoutBinding{projection_binding, view_binding, transform_binding, light_binding, view_pos_binding};
    const texture_bindings = [_]c.VkDescriptorSetLayoutBinding{texture_sampler_binding, diffuse_sampler_binding};

    var descriptor_set_layout: c.VkDescriptorSetLayout = undefined;
    var texture_descriptor_set_layout: c.VkDescriptorSetLayout = undefined;

    const descriptor_set_layout_info = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 5,
        .pBindings = bindings[0..].ptr,
    };

    const texture_descriptor_set_layout_info = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 2,
        .pBindings = texture_bindings[0..].ptr,
    };

    try vk.mapError(c.vkCreateDescriptorSetLayout(device.handle, &descriptor_set_layout_info, null, &descriptor_set_layout));
    try vk.mapError(c.vkCreateDescriptorSetLayout(device.handle, &texture_descriptor_set_layout_info, null, &texture_descriptor_set_layout));

    var set_layouts = [_]c.VkDescriptorSetLayout{descriptor_set_layout, texture_descriptor_set_layout};

    const layout_info: c.VkPipelineLayoutCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 2,
        .pSetLayouts = set_layouts[0..].ptr,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };

    var layout: c.VkPipelineLayout = undefined;

    try vk.mapError(c.vkCreatePipelineLayout(device.handle, &layout_info, null, @ptrCast(&layout)));

    const pipeline_info: c.VkGraphicsPipelineCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = shader_stage_infos.ptr,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly_info,
        .pViewportState = &viewport_state_info,
        .pRasterizationState = &rasterizer_info,
        .pMultisampleState = &multisampling_info,
        .pDepthStencilState = null,
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
        .descriptorCount = 2,
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

    const projection_buffer = try device.createBuffer(vk.BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(math.Matrix));

    var data: [*c]u8 = undefined;

    try vk.mapError(c.vkMapMemory(
        device.handle,
        projection_buffer.memory,
        0,
        projection_buffer.size,
        0,
        @ptrCast(&data),
    ));

    @memcpy(data[0..@sizeOf(math.Matrix)], std.mem.asBytes(&Camera.getProjection(swapchain.extent.width, swapchain.extent.height)));

    const descriptor_buffer_info = c.VkDescriptorBufferInfo{
        .buffer = projection_buffer.handle,
        .offset = 0,
        .range = projection_buffer.size,
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

    const view_buffer = try device.createBuffer(vk.BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(math.Matrix));

    var view_data: [*c]u8 = undefined;

    try vk.mapError(c.vkMapMemory(
        device.handle,
        view_buffer.memory,
        0,
        view_buffer.size,
        0,
        @ptrCast(&view_data),
    ));

    const view_descriptor_buffer_info = c.VkDescriptorBufferInfo{
        .buffer = view_buffer.handle,
        .offset = 0,
        .range = view_buffer.size,
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

    const transform_buffer = try device.createBuffer(vk.BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(math.Transform) - @sizeOf(math.Quaternion));

    var transform_data: [*c]u8 = undefined;

    try vk.mapError(c.vkMapMemory(
        device.handle,
        transform_buffer.memory,
        0,
        transform_buffer.size,
        0,
        @ptrCast(&transform_data),
    ));

    const transform_descriptor_buffer_info = c.VkDescriptorBufferInfo{
        .buffer = transform_buffer.handle,
        .offset = 0,
        .range = transform_buffer.size,
    };

    const write_transform_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 4,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .pBufferInfo = &transform_descriptor_buffer_info,
    };

    c.vkUpdateDescriptorSets(device.handle, 1, &write_transform_descriptor_set, 0, null);

    const light_buffer = try device.createBuffer(vk.BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf([3]f32));

    var light_data: [*c]u8 = undefined;

    try vk.mapError(c.vkMapMemory(
        device.handle,
        light_buffer.memory,
        0,
        light_buffer.size,
        0,
        @ptrCast(&light_data),
    ));

    const light_pos: [*]f32 = @alignCast(@ptrCast(light_data));

    const light_descriptor_buffer_info = c.VkDescriptorBufferInfo{
        .buffer = light_buffer.handle,
        .offset = 0,
        .range = light_buffer.size,
    };

    const write_light_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 2,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .pBufferInfo = &light_descriptor_buffer_info,
    };

    c.vkUpdateDescriptorSets(device.handle, 1, &write_light_descriptor_set, 0, null);

    const view_pos_buffer = try device.createBuffer(vk.BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf([3]f32));

    var view_pos_data: [*c]u8 = undefined;

    try vk.mapError(c.vkMapMemory(
        device.handle,
        view_pos_buffer.memory,
        0,
        view_pos_buffer.size,
        0,
        @ptrCast(&view_pos_data),
    ));

    const view_pos_descriptor_buffer_info = c.VkDescriptorBufferInfo{
        .buffer = view_pos_buffer.handle,
        .offset = 0,
        .range = view_pos_buffer.size,
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

    return Self{
        .layout = layout,
        .handle = pipeline,
        .texture_set_layout = texture_descriptor_set_layout,
        .descriptor_pool = descriptor_pool,
        .descriptor_set = descriptor_set,
        .descriptor_set_layout = descriptor_set_layout,
        .projection_buffer = projection_buffer,
        .view_buffer = view_buffer,
        .view_memory = view_data,
        .light_buffer = light_buffer,
        .view_pos_memory = view_pos_data,
        .transform_memory = transform_data,
        .texture_sampler = try vk.Sampler.init(device),
        .diffuse_sampler = try vk.Sampler.init(device),
        .textures = std.ArrayList(c.VkDescriptorSet).init(allocator),
        .light_pos = light_pos,
    };
}

pub fn addTexture(self: *Self, device: anytype, texture: Texture, diffuse: Texture) !usize {
    var set_layouts = [_]c.VkDescriptorSetLayout{self.texture_set_layout};
    const descriptor_allocate_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = self.descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = set_layouts[0..].ptr,
    };

    var descriptor_set: c.VkDescriptorSet = undefined;
    try vk.mapError(c.vkAllocateDescriptorSets(device.handle, &descriptor_allocate_info, &descriptor_set));

    const texture_info: c.VkDescriptorImageInfo = .{
        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = texture.image_view,
        .sampler = self.texture_sampler.handle,
    };

    const diffuse_info: c.VkDescriptorImageInfo = .{
        .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = diffuse.image_view,
        .sampler = self.diffuse_sampler.handle,
    };

    const write_texture_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 0,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &texture_info,
    };

    const write_diffuse_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 1,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &diffuse_info,
    };

    const writes = [_]c.VkWriteDescriptorSet {write_texture_descriptor_set, write_diffuse_descriptor_set};

    c.vkUpdateDescriptorSets(device.handle, 2, writes[0..].ptr, 0, null);

    const index = self.textures.items.len;
    try self.textures.append(descriptor_set);

    return index;
}

pub fn bind(self: Self, device: vk.Device, frame: usize) void {
    std.debug.assert(frame < 2);
    c.vkCmdBindPipeline(device.command_buffers[frame], c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.handle);
}

pub fn deinit(self: Self, device: vk.Device) void {
    self.textures.deinit();
    self.texture_sampler.deinit(device);
    self.diffuse_sampler.deinit(device);
    self.projection_buffer.deinit(device.handle);
    c.vkDestroyDescriptorSetLayout(device.handle, self.descriptor_set_layout, null);
    c.vkDestroyDescriptorPool(device.handle, self.descriptor_pool, null);
    c.vkDestroyPipeline(device.handle, self.handle, null);
    c.vkDestroyPipelineLayout(device.handle, self.layout, null);
}
