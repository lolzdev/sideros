const std = @import("std");
const vk = @import("vulkan.zig");
const c = vk.c;
const ui = @import("ui");

const Self = @This();

const max_rects = 256;
const vertices_per_rect = 6;

const Vertex = extern struct {
    position: @Vector(2, f32),
    color: ui.Color,

    fn bindingDescription() c.VkVertexInputBindingDescription {
        return .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        };
    }

    fn attributeDescriptions() []const c.VkVertexInputAttributeDescription {
        return &.{
            .{
                .location = 0,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Vertex, "position"),
            },
            .{
                .location = 1,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            },
        };
    }
};

layout: c.VkPipelineLayout,
handle: c.VkPipeline,
vertex_buffer: vk.Buffer,
mapped_vertices: []Vertex,
allocator: std.mem.Allocator,

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
    const shader_stage_infos = [_]c.VkPipelineShaderStageCreateInfo{ vertex_shader_stage_info, fragment_shader_stage_info };

    const vertex_binding = Vertex.bindingDescription();
    const vertex_attributes = Vertex.attributeDescriptions();
    const vertex_input_info: c.VkPipelineVertexInputStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &vertex_binding,
        .vertexAttributeDescriptionCount = @intCast(vertex_attributes.len),
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
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain.extent,
    };
    const viewport_state_info: c.VkPipelineViewportStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    const dynamic_states = [_]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };
    const dynamic_state_info: c.VkPipelineDynamicStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamic_states.len,
        .pDynamicStates = dynamic_states[0..].ptr,
    };

    const rasterizer_info: c.VkPipelineRasterizationStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = c.VK_CULL_MODE_NONE,
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
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
    };
    const color_blend_info: c.VkPipelineColorBlendStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
    };

    const depth_stencil: c.VkPipelineDepthStencilStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = c.VK_FALSE,
        .depthWriteEnable = c.VK_FALSE,
        .depthCompareOp = c.VK_COMPARE_OP_ALWAYS,
        .depthBoundsTestEnable = c.VK_FALSE,
        .stencilTestEnable = c.VK_FALSE,
    };

    const push_constant: c.VkPushConstantRange = .{
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
        .offset = 0,
        .size = @sizeOf([2]f32),
    };
    const layout_info: c.VkPipelineLayoutCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_constant,
    };

    var layout: c.VkPipelineLayout = undefined;
    try vk.mapError(c.vkCreatePipelineLayout(device.handle, &layout_info, null, &layout));

    const pipeline_info: c.VkGraphicsPipelineCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = shader_stage_infos.len,
        .pStages = shader_stage_infos[0..].ptr,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly_info,
        .pViewportState = &viewport_state_info,
        .pRasterizationState = &rasterizer_info,
        .pMultisampleState = &multisampling_info,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &color_blend_info,
        .pDynamicState = &dynamic_state_info,
        .layout = layout,
        .renderPass = render_pass.handle,
        .subpass = 0,
        .basePipelineHandle = null,
    };

    var handle: c.VkPipeline = undefined;
    try vk.mapError(c.vkCreateGraphicsPipelines(device.handle, null, 1, &pipeline_info, null, &handle));

    const vertex_buffer = try device.initBuffer(
        .{ .vertex_buffer = true },
        .{ .host_visible = true, .host_coherent = true },
        @sizeOf(Vertex) * max_rects * vertices_per_rect,
    );

    var mapped: [*c]u8 = undefined;
    try vk.mapError(c.vkMapMemory(device.handle, vertex_buffer.memory, 0, vertex_buffer.size, 0, @ptrCast(&mapped)));

    return .{
        .layout = layout,
        .handle = handle,
        .vertex_buffer = vertex_buffer,
        .mapped_vertices = @as([*]Vertex, @ptrCast(@alignCast(mapped)))[0 .. max_rects * vertices_per_rect],
        .allocator = allocator,
    };
}

pub fn draw(self: *Self, device: vk.Device, swapchain: vk.Swapchain, frame: usize, context: *const ui.Context) void {
    const rect_count = @min(context.draw_list.items.len, max_rects);
    var vertex_count: usize = 0;

    for (context.draw_list.items[0..rect_count]) |command| {
        const rect = command.rect;
        const x0 = rect.x;
        const y0 = rect.y;
        const x1 = rect.x + rect.width;
        const y1 = rect.y + rect.height;
        const color = command.color;

        const vertices = [_]Vertex{
            .{ .position = .{ x0, y0 }, .color = color },
            .{ .position = .{ x0, y1 }, .color = color },
            .{ .position = .{ x1, y0 }, .color = color },
            .{ .position = .{ x1, y0 }, .color = color },
            .{ .position = .{ x0, y1 }, .color = color },
            .{ .position = .{ x1, y1 }, .color = color },
        };
        @memcpy(self.mapped_vertices[vertex_count .. vertex_count + vertices_per_rect], vertices[0..]);
        vertex_count += vertices_per_rect;
    }

    if (vertex_count == 0) {
        return;
    }

    const command_buffer = device.command_buffers[frame];
    c.vkCmdBindPipeline(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.handle);
    const offset: u64 = 0;
    c.vkCmdBindVertexBuffers(command_buffer, 0, 1, &self.vertex_buffer.handle, &offset);
    const viewport = [2]f32{
        @floatFromInt(swapchain.extent.width),
        @floatFromInt(swapchain.extent.height),
    };
    c.vkCmdPushConstants(command_buffer, self.layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf([2]f32), @ptrCast(@constCast(&viewport)));
    c.vkCmdDraw(command_buffer, @intCast(vertex_count), 1, 0, 0);
}

pub fn deinit(self: *Self, device: vk.Device) void {
    c.vkUnmapMemory(device.handle, self.vertex_buffer.memory);
    self.vertex_buffer.deinit(device.handle);
    c.vkDestroyPipeline(device.handle, self.handle, null);
    c.vkDestroyPipelineLayout(device.handle, self.layout, null);
}
