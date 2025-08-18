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
vertex_buffer: vk.Buffer,
index_buffer: vk.Buffer,
texture_set_layout: c.VkDescriptorSetLayout,
descriptor_pool: c.VkDescriptorPool,
descriptor_set: c.VkDescriptorSet,
descriptor_set_layout: c.VkDescriptorSetLayout,
projection_buffer: vk.Buffer,
view_buffer: vk.Buffer,
view_memory: [*c]u8,
transform_buffer: vk.DynamicBuffer(math.Transform),
view_pos_memory: [*c]u8,
view_pos_buffer: vk.Buffer,
diffuse_sampler: vk.Sampler,
specular_sampler: vk.Sampler,
textures: c.VkDescriptorSet,
directional_light: *lights.DirectionalLight,
directional_light_buffer: vk.Buffer,
point_lights: []lights.PointLight,
point_lights_buffer: vk.Buffer,

device: vk.Device,
render_pass: vk.RenderPass,
swapchain: vk.Swapchain,

const Self = @This();

pub const Builder = struct {
    current_vertex: i32 = 0,
    current_index: u32 = 0,
    vertex_buffers: std.ArrayList(vk.Buffer),
    index_buffers: std.ArrayList(vk.Buffer),
    diffuse_textures: std.ArrayList(vk.Texture),
    specular_textures: std.ArrayList(vk.Texture),
    device: vk.Device,
    allocator: Allocator,

    pub fn init(allocator: Allocator, device: vk.Device) Builder {
        return .{
            .vertex_buffers = std.ArrayList(vk.Buffer).empty,
            .index_buffers = std.ArrayList(vk.Buffer).empty,
            .diffuse_textures = std.ArrayList(vk.Texture).empty,
            .specular_textures = std.ArrayList(vk.Texture).empty,
            .device = device,
            .allocator = allocator,
        };
    }

    pub fn addMesh(self: *Builder, path: []const u8) !Mesh {
        const gltf_data = try gltf.parseFile(self.allocator, path);

        const vertex_buffer = try createVertexBuffer(self.allocator, self.device, gltf_data);
        const index_buffer = try createIndexBuffer(self.allocator, self.device, gltf_data);
        const vertex_cursor = self.current_vertex;
        const index_cursor = self.current_index;
        self.current_vertex += @intCast(vertex_buffer.size);
        self.current_index += @intCast(index_buffer.size);
        try self.vertex_buffers.append(self.allocator, vertex_buffer);
        try self.index_buffers.append(self.allocator, index_buffer);

        return .{
            .vertex_buffer = vertex_cursor,
            .index_buffer = index_cursor,
            .index_count = @intCast(index_buffer.size / @sizeOf(u16)),
        };
    }


    pub fn addTexture(self: *Builder, diffuse: Texture, specular: Texture) !usize {
        const index = self.diffuse_textures.items.len;
        try self.diffuse_textures.append(self.allocator, diffuse);
        try self.specular_textures.append(self.allocator, specular);

        return index;
    }

    pub fn build(self: *Builder, swapchain: vk.Swapchain, render_pass: vk.RenderPass, vertex_shader: c.VkShaderModule, fragment_shader: c.VkShaderModule) !Self {
        const vertex_buffer, const index_buffer = try self.createBuffers();
        const pipeline = try Self.init(self.allocator, self.device, swapchain, render_pass, vertex_shader, fragment_shader, vertex_buffer, index_buffer, self.diffuse_textures, self.specular_textures);
        self.diffuse_textures.deinit(self.allocator);
        self.specular_textures.deinit(self.allocator);
        return pipeline;
    }

    pub fn createBuffers(self: *Builder) !struct { vk.Buffer, vk.Buffer } {
        const vertex_buffer = try self.device.initBuffer(vk.BufferUsage{ .vertex_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @intCast(self.current_vertex));

        var vertex_cursor = @as(usize, 0);
        for (self.vertex_buffers.items) |buffer| {
            try buffer.copyTo(self.device, vertex_buffer, vertex_cursor);
            vertex_cursor += buffer.size;
            buffer.deinit(self.device.handle);
        }

        const index_buffer = try self.device.initBuffer(vk.BufferUsage{ .index_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, self.current_index);

        var index_cursor = @as(usize, 0);
        for (self.index_buffers.items) |buffer| {
            try buffer.copyTo(self.device, index_buffer, index_cursor);
            index_cursor += buffer.size;
            buffer.deinit(self.device.handle);
        }

        self.vertex_buffers.deinit(self.allocator);
        self.index_buffers.deinit(self.allocator);

        return .{
            vertex_buffer,
            index_buffer,
        };
    }

    fn createVertexBuffer(allocator: Allocator, device: vk.Device, gltf_data: anytype) !vk.Buffer {
        const vertices = gltf_data.vertices;
        const normals = gltf_data.normals;
        const uvs = gltf_data.uvs;
        defer allocator.free(uvs);
        defer allocator.free(normals);
        defer allocator.free(vertices);

        const final_array = try allocator.alloc([8]f32, vertices.len);
        defer allocator.free(final_array);

        for (vertices, normals, uvs, final_array) |vertex, normal, uv, *final| {
            final[0] = vertex[0];
            final[1] = vertex[1];
            final[2] = vertex[2];

            final[3] = normal[0];
            final[4] = normal[1];
            final[5] = normal[2];

            final[6] = uv[0];
            final[7] = uv[1];
        }

        var data: [*c]?*anyopaque = null;

        const buffer = try device.initBuffer(vk.BufferUsage{ .transfer_src = true }, vk.BufferFlags{ .host_visible = true, .host_coherent = true }, @sizeOf([8]f32) * vertices.len);

        try vk.mapError(vk.c.vkMapMemory(
            device.handle,
            buffer.memory,
            0,
            buffer.size,
            0,
            @ptrCast(&data),
        ));

        if (data) |ptr| {
            const gpu_vertices: [*]Mesh.Vertex = @ptrCast(@alignCast(ptr));

            @memcpy(gpu_vertices, @as([]Mesh.Vertex, @ptrCast(final_array[0..])));
        }

        vk.c.vkUnmapMemory(device.handle, buffer.memory);

        const vertex_buffer = try device.initBuffer(vk.BufferUsage{ .vertex_buffer = true, .transfer_dst = true, .transfer_src = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(Mesh.Vertex) * vertices.len);

        try buffer.copyTo(device, vertex_buffer, 0);
        buffer.deinit(device.handle);

        return vertex_buffer;
    }

    pub fn createIndexBuffer(allocator: Allocator, device: anytype, gltf_data: anytype) !vk.Buffer {
        const indices = gltf_data.indices;
        defer allocator.free(indices);

        var data: [*c]?*anyopaque = null;

        const buffer = try device.initBuffer(vk.BufferUsage{ .transfer_src = true }, vk.BufferFlags{ .host_visible = true, .host_coherent = true }, @sizeOf(u16) * indices.len);

        try vk.mapError(vk.c.vkMapMemory(
            device.handle,
            buffer.memory,
            0,
            buffer.size,
            0,
            @ptrCast(&data),
        ));

        if (data) |ptr| {
            const gpu_indices: [*]u16 = @ptrCast(@alignCast(ptr));

            @memcpy(gpu_indices, indices[0..]);
        }

        vk.c.vkUnmapMemory(device.handle, buffer.memory);

        const index_buffer = try device.initBuffer(vk.BufferUsage{ .index_buffer = true, .transfer_dst = true, .transfer_src = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(u16) * indices.len);

        try buffer.copyTo(device, index_buffer, 0);
        buffer.deinit(device.handle);

        return index_buffer;
    }

};

pub fn init(allocator: Allocator, device: vk.Device, swapchain: vk.Swapchain, render_pass: vk.RenderPass, vertex_shader: c.VkShaderModule, fragment_shader: c.VkShaderModule, vertex_buffer: vk.Buffer, index_buffer: vk.Buffer, diffuse_textures: std.ArrayList(vk.Texture), specular_textures: std.ArrayList(vk.Texture)) !Self {
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

    const transform_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 4,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
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

    const diffuse_sampler_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = @intCast(diffuse_textures.items.len),
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const specular_sampler_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = @intCast(specular_textures.items.len),
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const bindings = [_]c.VkDescriptorSetLayoutBinding{projection_binding, view_binding, transform_binding, directional_light_binding, point_lights_binding, view_pos_binding};
    const texture_bindings = [_]c.VkDescriptorSetLayoutBinding{diffuse_sampler_binding, specular_sampler_binding};

    var descriptor_set_layout: c.VkDescriptorSetLayout = undefined;
    var texture_descriptor_set_layout: c.VkDescriptorSetLayout = undefined;

    const descriptor_set_layout_info = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 6,
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

    const lights_range: c.VkPushConstantRange = .{
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .offset = 0,
        .size = 4,
    };

    const transform_range: c.VkPushConstantRange = .{
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
        .offset = 4,
        .size = 4,
    };

    const range: [2]c.VkPushConstantRange = .{lights_range, transform_range};

    const layout_info: c.VkPipelineLayoutCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 2,
        .pSetLayouts = set_layouts[0..].ptr,
        .pushConstantRangeCount = 2,
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
        .descriptorCount = 6,
    };

    const sampler_size = c.VkDescriptorPoolSize{
        .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = @intCast(diffuse_textures.items.len + specular_textures.items.len),
    };

    const transforms_size = c.VkDescriptorPoolSize{
        .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = 1,
    };

    const sizes = [_]c.VkDescriptorPoolSize {size, sampler_size, transforms_size};

    const descriptor_pool_info = c.VkDescriptorPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 2,
        .poolSizeCount = 3,
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

    const projection_buffer = try device.initBuffer(vk.BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(math.Matrix));

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

    const view_buffer = try device.initBuffer(vk.BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(math.Matrix));

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

    const transform_buffer = try vk.DynamicBuffer(math.Transform).init(allocator, device, vk.BufferUsage{ .storage_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, descriptor_set, 4);

    const directional_light_buffer = try device.initBuffer(vk.BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(lights.DirectionalLight));

    var directional_light_data: [*c]u8 = undefined;

    try vk.mapError(c.vkMapMemory(
        device.handle,
        directional_light_buffer.memory,
        0,
        directional_light_buffer.size,
        0,
        @ptrCast(&directional_light_data),
    ));

    const directional_light: *lights.DirectionalLight = @alignCast(@ptrCast(directional_light_data));

    const directional_light_descriptor_buffer_info = c.VkDescriptorBufferInfo{
        .buffer = directional_light_buffer.handle,
        .offset = 0,
        .range = directional_light_buffer.size,
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

    const point_lights_buffer = try device.initBuffer(vk.BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(lights.PointLight) * max_point_lights);

    var point_lights_data: [*c]u8 = undefined;

    try vk.mapError(c.vkMapMemory(
        device.handle,
        point_lights_buffer.memory,
        0,
        point_lights_buffer.size,
        0,
        @ptrCast(&point_lights_data),
    ));

    const point_lights: []lights.PointLight = @as([*]lights.PointLight, @alignCast(@ptrCast(point_lights_data)))[0..max_point_lights];

    var point_lights_descriptor_buffer_info: c.VkDescriptorBufferInfo = undefined;
    point_lights_descriptor_buffer_info.buffer = point_lights_buffer.handle;
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

    const view_pos_buffer = try device.initBuffer(vk.BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf([3]f32));

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

    const diffuse_sampler = try vk.Sampler.init(device, .linear);
    const specular_sampler = try vk.Sampler.init(device, .linear);

    const texture_descriptor_allocate_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &texture_descriptor_set_layout,
    };

    var texture_descriptor_set: c.VkDescriptorSet = undefined;
    try vk.mapError(c.vkAllocateDescriptorSets(device.handle, &texture_descriptor_allocate_info, &texture_descriptor_set));

    var diffuse_infos = std.ArrayList(c.VkDescriptorImageInfo).empty;
    defer diffuse_infos.deinit(allocator);
    var specular_infos = std.ArrayList(c.VkDescriptorImageInfo).empty;
    defer specular_infos.deinit(allocator);

    for (diffuse_textures.items, specular_textures.items) |diffuse, specular| {
        try diffuse_infos.append(allocator, .{
            .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = diffuse.image_view,
            .sampler = diffuse_sampler.handle,
        });

        try specular_infos.append(allocator, .{
            .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = specular.image_view,
            .sampler = specular_sampler.handle,
        });
    }

    const write_diffuse_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = texture_descriptor_set,
        .dstBinding = 0,
        .dstArrayElement = 0,
        .descriptorCount = @intCast(diffuse_infos.items.len),
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = diffuse_infos.items[0..].ptr,
    };

    const write_specular_descriptor_set = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = texture_descriptor_set,
        .dstBinding = 1,
        .dstArrayElement = 0,
        .descriptorCount = @intCast(specular_infos.items.len),
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = specular_infos.items[0..].ptr,
    };

    const writes = [_]c.VkWriteDescriptorSet {write_diffuse_descriptor_set, write_specular_descriptor_set};
    c.vkUpdateDescriptorSets(device.handle, 2, writes[0..].ptr, 0, null);

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
        .view_pos_memory = view_pos_data,
        .view_pos_buffer = view_pos_buffer,
        .transform_buffer = transform_buffer,
        .textures = texture_descriptor_set,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .directional_light = directional_light,
        .directional_light_buffer = directional_light_buffer,
        .point_lights = point_lights,
        .point_lights_buffer = point_lights_buffer,
        .diffuse_sampler = diffuse_sampler,
        .specular_sampler = specular_sampler,
        .device = device,
        .swapchain = swapchain,
        .render_pass = render_pass,
    };
}

pub fn bind(self: Self, device: vk.Device, frame: usize) void {
    std.debug.assert(frame < 2);
    c.vkCmdBindPipeline(device.command_buffers[frame], c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.handle);
}

pub fn deinit(self: Self, device: vk.Device) void {
    self.diffuse_sampler.deinit(device);
    self.specular_sampler.deinit(device);
    self.projection_buffer.deinit(device.handle);
    c.vkDestroyDescriptorSetLayout(device.handle, self.descriptor_set_layout, null);
    c.vkDestroyDescriptorPool(device.handle, self.descriptor_pool, null);
    c.vkDestroyPipeline(device.handle, self.handle, null);
    c.vkDestroyPipelineLayout(device.handle, self.layout, null);
}
