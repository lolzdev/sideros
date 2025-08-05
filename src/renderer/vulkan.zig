pub const Texture = @import("Texture.zig");

const std = @import("std");
pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});
const math = @import("math");
const Mesh = @import("Mesh.zig");
const Camera = @import("Camera.zig");
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");
const debug = (builtin.mode == .Debug);

const Uniform = struct {
    proj: math.Matrix,
    view: math.Matrix,
    model: math.Matrix,
};

const validation_layers: []const [*c]const u8 = if (!debug) &[0][*c]const u8{} else &[_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const device_extensions: []const [*c]const u8 = &[_][*c]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

pub const Error = error{
    out_of_host_memory,
    out_of_device_memory,
    initialization_failed,
    layer_not_present,
    extension_not_present,
    incompatible_driver,
    unknown_error,
};

pub fn mapError(result: c_int) !void {
    return switch (result) {
        c.VK_SUCCESS => {},
        c.VK_ERROR_OUT_OF_HOST_MEMORY => Error.out_of_host_memory,
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => Error.out_of_device_memory,
        c.VK_ERROR_INITIALIZATION_FAILED => Error.initialization_failed,
        c.VK_ERROR_LAYER_NOT_PRESENT => Error.layer_not_present,
        c.VK_ERROR_EXTENSION_NOT_PRESENT => Error.extension_not_present,
        c.VK_ERROR_INCOMPATIBLE_DRIVER => Error.incompatible_driver,
        else => Error.unknown_error,
    };
}

pub const BufferUsage = packed struct(u32) {
    transfer_src: bool = false,
    transfer_dst: bool = false,
    uniform_texel_buffer: bool = false,
    storage_texel_buffer: bool = false,
    uniform_buffer: bool = false,
    storage_buffer: bool = false,
    index_buffer: bool = false,
    vertex_buffer: bool = false,
    indirect_buffer: bool = false,
    _padding: enum(u23) { unset } = .unset,
};

pub const BufferFlags = packed struct(u32) {
    device_local: bool = false,
    host_visible: bool = false,
    host_coherent: bool = false,
    host_cached: bool = false,
    lazily_allocated: bool = false,
    _padding: enum(u27) { unset } = .unset,
};

pub const Instance = struct {
    handle: c.VkInstance,
};

pub const Buffer = struct {
    handle: c.VkBuffer,
    memory: c.VkDeviceMemory,
    size: usize,

    pub fn copyTo(self: Buffer, device: anytype, dest: Buffer) !void {
        const command_buffer = try device.beginSingleTimeCommands();

        const copy_region: c.VkBufferCopy = .{
            .srcOffset = 0,
            .dstOffset = 0,
            .size = self.size,
        };

        c.vkCmdCopyBuffer(command_buffer, self.handle, dest.handle, 1, &copy_region);

        try device.endSingleTimeCommands(command_buffer);
    }

    pub fn destroy(self: Buffer, device_handle: c.VkDevice) void {
        c.vkDestroyBuffer(device_handle, self.handle, null);
        c.vkFreeMemory(device_handle, self.memory, null);
    }
};

pub const Sampler = struct {
    handle: c.VkSampler,

    pub fn init(device: anytype) !Sampler {
        var sampler: c.VkSampler = undefined;

        const create_info: c.VkSamplerCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = c.VK_FILTER_LINEAR,
            .minFilter = c.VK_FILTER_LINEAR,
            .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
            .unnormalizedCoordinates = c.VK_FALSE,
            .compareEnable = c.VK_FALSE,
            .compareOp = c.VK_COMPARE_OP_ALWAYS,
            .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
            .mipLodBias = 0.0,
            .minLod = 0.0,
            .maxLod = 0.0,
            .anisotropyEnable = c.VK_FALSE,
            .maxAnisotropy = 1.0,
        };

        try mapError(c.vkCreateSampler(device.handle, &create_info, null, &sampler));

        return .{
            .handle = sampler,
        };
    }

    pub fn deinit(self: Sampler, device: anytype) void {
        c.vkDestroySampler(device.handle, self.handle, null);
    }
};

pub fn RenderPass(comptime n: usize) type {
    return struct {
        handle: c.VkRenderPass,

        const Self = @This();

        pub fn create(allocator: Allocator, device: Device(n), surface: Surface, physical_device: PhysicalDevice) !Self {
            const color_attachment: c.VkAttachmentDescription = .{
                .format = (try Swapchain(n).pickFormat(allocator, surface, physical_device)).format,
                .samples = c.VK_SAMPLE_COUNT_1_BIT,
                .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
                .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            };

            const color_attachment_reference: c.VkAttachmentReference = .{
                .attachment = 0,
                .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            };

            const subpass: c.VkSubpassDescription = .{
                .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                .colorAttachmentCount = 1,
                .pColorAttachments = &color_attachment_reference,
            };

            const dependency: c.VkSubpassDependency = .{
                .srcSubpass = c.VK_SUBPASS_EXTERNAL,
                .dstSubpass = 0,
                .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                .srcAccessMask = 0,
                .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            };

            const render_pass_info: c.VkRenderPassCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
                .attachmentCount = 1,
                .pAttachments = &color_attachment,
                .subpassCount = 1,
                .pSubpasses = &subpass,
                .dependencyCount = 1,
                .pDependencies = &dependency,
            };

            var render_pass: c.VkRenderPass = undefined;

            try mapError(c.vkCreateRenderPass(device.handle, &render_pass_info, null, &render_pass));

            return Self{
                .handle = render_pass,
            };
        }

        pub fn begin(self: Self, swapchain: Swapchain(n), device: Device(n), image: usize, frame: usize) void {
            std.debug.assert(frame < n);
            const clear_color: c.VkClearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } };

            const begin_info: c.VkRenderPassBeginInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                .renderPass = self.handle,
                .framebuffer = swapchain.framebuffers[image],
                .renderArea = .{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = swapchain.extent,
                },
                .clearValueCount = 1,
                .pClearValues = &clear_color,
            };

            c.vkCmdBeginRenderPass(device.command_buffers[frame], &begin_info, c.VK_SUBPASS_CONTENTS_INLINE);
        }

        pub fn end(self: Self, device: Device(n), frame: usize) void {
            _ = self;
            std.debug.assert(frame < n);
            c.vkCmdEndRenderPass(device.command_buffers[frame]);
        }

        pub fn destroy(self: Self, device: Device(n)) void {
            c.vkDestroyRenderPass(device.handle, self.handle, null);
        }
    };
}

pub fn GraphicsPipeline(comptime n: usize) type {
    return struct {
        layout: c.VkPipelineLayout,
        handle: c.VkPipeline,
        texture_set_layout: c.VkDescriptorSetLayout,
        descriptor_pool: c.VkDescriptorPool,
        descriptor_set: c.VkDescriptorSet,
        descriptor_set_layout: c.VkDescriptorSetLayout,
        projection_buffer: Buffer,
        light_buffer: Buffer,
        view_buffer: Buffer,
        view_memory: [*c]u8,
        view_pos_memory: [*c]u8,
        texture_sampler: Sampler,
        diffuse_sampler: Sampler,
        textures: std.ArrayList(c.VkDescriptorSet),
        light_pos: [*]f32,

        const Self = @This();

        pub fn create(allocator: std.mem.Allocator, device: Device(n), swapchain: Swapchain(n), render_pass: RenderPass(n), vertex_shader: c.VkShaderModule, fragment_shader: c.VkShaderModule) !Self {
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
                .frontFace = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
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

            const bindings = [_]c.VkDescriptorSetLayoutBinding{projection_binding, view_binding, light_binding, view_pos_binding};
            const texture_bindings = [_]c.VkDescriptorSetLayoutBinding{texture_sampler_binding, diffuse_sampler_binding};

            var descriptor_set_layout: c.VkDescriptorSetLayout = undefined;
            var texture_descriptor_set_layout: c.VkDescriptorSetLayout = undefined;

            const descriptor_set_layout_info = c.VkDescriptorSetLayoutCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                .bindingCount = 4,
                .pBindings = bindings[0..].ptr,
            };

            const texture_descriptor_set_layout_info = c.VkDescriptorSetLayoutCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                .bindingCount = 2,
                .pBindings = texture_bindings[0..].ptr,
            };

            try mapError(c.vkCreateDescriptorSetLayout(device.handle, &descriptor_set_layout_info, null, &descriptor_set_layout));
            try mapError(c.vkCreateDescriptorSetLayout(device.handle, &texture_descriptor_set_layout_info, null, &texture_descriptor_set_layout));

            var set_layouts = [_]c.VkDescriptorSetLayout{descriptor_set_layout, texture_descriptor_set_layout};

            const layout_info: c.VkPipelineLayoutCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                .setLayoutCount = 2,
                .pSetLayouts = set_layouts[0..].ptr,
                .pushConstantRangeCount = 0,
                .pPushConstantRanges = null,
            };

            var layout: c.VkPipelineLayout = undefined;

            try mapError(c.vkCreatePipelineLayout(device.handle, &layout_info, null, @ptrCast(&layout)));

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

            try mapError(c.vkCreateGraphicsPipelines(device.handle, null, 1, &pipeline_info, null, @ptrCast(&pipeline)));

            const size = c.VkDescriptorPoolSize{
                .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = 4,
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

            try mapError(c.vkCreateDescriptorPool(device.handle, &descriptor_pool_info, null, &descriptor_pool));

            const descriptor_allocate_info = c.VkDescriptorSetAllocateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                .descriptorPool = descriptor_pool,
                .descriptorSetCount = 1,
                .pSetLayouts = set_layouts[0..].ptr,
            };

            var descriptor_set: c.VkDescriptorSet = undefined;

            try mapError(c.vkAllocateDescriptorSets(device.handle, &descriptor_allocate_info, &descriptor_set));

            const projection_buffer = try device.createBuffer(BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, BufferFlags{ .device_local = true }, @sizeOf(math.Matrix));

            var data: [*c]u8 = undefined;

            try mapError(c.vkMapMemory(
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

            const view_buffer = try device.createBuffer(BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, BufferFlags{ .device_local = true }, @sizeOf(math.Matrix));

            var view_data: [*c]u8 = undefined;

            try mapError(c.vkMapMemory(
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

            const light_buffer = try device.createBuffer(BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, BufferFlags{ .device_local = true }, @sizeOf([3]f32));

            var light_data: [*c]u8 = undefined;

            try mapError(c.vkMapMemory(
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

            const view_pos_buffer = try device.createBuffer(BufferUsage{ .uniform_buffer = true, .transfer_dst = true }, BufferFlags{ .device_local = true }, @sizeOf([3]f32));

            var view_pos_data: [*c]u8 = undefined;

            try mapError(c.vkMapMemory(
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
                .texture_sampler = try Sampler.init(device),
                .diffuse_sampler = try Sampler.init(device),
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
            try mapError(c.vkAllocateDescriptorSets(device.handle, &descriptor_allocate_info, &descriptor_set));

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

        pub fn bind(self: Self, device: Device(n), frame: usize) void {
            std.debug.assert(frame < n);
            c.vkCmdBindPipeline(device.command_buffers[frame], c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.handle);
        }

        pub fn destroy(self: Self, device: Device(n)) void {
            self.textures.deinit();
            self.texture_sampler.deinit(device);
            self.diffuse_sampler.deinit(device);
            self.projection_buffer.destroy(device.handle);
            c.vkDestroyDescriptorSetLayout(device.handle, self.descriptor_set_layout, null);
            c.vkDestroyDescriptorPool(device.handle, self.descriptor_pool, null);
            c.vkDestroyPipeline(device.handle, self.handle, null);
            c.vkDestroyPipelineLayout(device.handle, self.layout, null);
        }
    };
}

//pub const Shader = struct {
//    handle: c.VkShaderModule,
//
//    pub fn create(comptime name: []const u8, device: Device) !Shader {
//        const code = @embedFile(name);
//
//        const create_info: c.VkShaderModuleCreateInfo = .{
//            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
//            .codeSize = code.len,
//            .pCode = @ptrCast(@alignCast(code)),
//        };
//
//        var shader_module: c.VkShaderModule = undefined;
//
//        try mapError(c.vkCreateShaderModule(device.handle, &create_info, null, @ptrCast(&shader_module)));
//
//        return Shader{
//            .handle = shader_module,
//        };
//    }
//
//    pub fn destroy(self: Shader, device: Device) void {
//        c.vkDestroyShaderModule(device.handle, self.handle, null);
//    }
//};

pub fn Swapchain(comptime n: usize) type {
    return struct {
        handle: c.VkSwapchainKHR,
        images: []c.VkImage,
        image_views: []c.VkImageView,
        format: c.VkSurfaceFormatKHR,
        extent: c.VkExtent2D,
        framebuffers: []c.VkFramebuffer,

        allocator: Allocator,

        const Self = @This();

        // TODO: This should not be part of the Swapchain?
        pub fn pickFormat(allocator: Allocator, surface: Surface, physical_device: PhysicalDevice) !c.VkSurfaceFormatKHR {
            const formats = try surface.formats(allocator, physical_device);
            defer allocator.free(formats);
            var format: ?c.VkSurfaceFormatKHR = null;

            for (formats) |fmt| {
                if (fmt.format == c.VK_FORMAT_B8G8R8A8_SRGB and fmt.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                    format = fmt;
                }
            }

            if (format == null) {
                format = formats[0];
            }

            return format.?;
        }

        // TODO: Allow to recreate so Window can be resized
        pub fn create(allocator: Allocator, surface: Surface, device: Device(n), physical_device: PhysicalDevice, render_pass: RenderPass(n)) !Self {
            const present_modes = try surface.presentModes(allocator, physical_device);
            defer allocator.free(present_modes);
            const capabilities = try surface.capabilities(physical_device);
            var present_mode: ?c.VkPresentModeKHR = null;
            var extent: c.VkExtent2D = undefined;
            const format = try Self.pickFormat(allocator, surface, physical_device);

            for (present_modes) |mode| {
                if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
                    present_mode = mode;
                }
            }

            if (present_mode == null) {
                present_mode = c.VK_PRESENT_MODE_FIFO_KHR;
            }

            if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
                extent = capabilities.currentExtent;
            } else {
                const width: u32, const height: u32 = .{ 800, 600 };

                extent = .{
                    .width = @intCast(width),
                    .height = @intCast(height),
                };

                extent.width = std.math.clamp(extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
                extent.height = std.math.clamp(extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);
            }

            var create_info: c.VkSwapchainCreateInfoKHR = .{
                .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
                .surface = surface.handle,
                .minImageCount = capabilities.minImageCount + 1,
                .imageFormat = format.format,
                .imageColorSpace = format.colorSpace,
                .imageExtent = extent,
                .imageArrayLayers = 1,
                .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
                .preTransform = capabilities.currentTransform,
                .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
                .presentMode = present_mode.?,
                .clipped = c.VK_TRUE,
                .oldSwapchain = null,
            };

            const graphics_family = try physical_device.graphicsQueue(allocator);
            const present_family = try physical_device.presentQueue(surface, allocator);
            const family_indices: []const u32 = &.{ graphics_family, present_family };

            if (graphics_family != present_family) {
                create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
                create_info.queueFamilyIndexCount = @intCast(family_indices.len);
                create_info.pQueueFamilyIndices = family_indices.ptr;
            } else {
                create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
                create_info.queueFamilyIndexCount = 0;
                create_info.pQueueFamilyIndices = null;
            }

            var swapchain: c.VkSwapchainKHR = undefined;

            try mapError(c.vkCreateSwapchainKHR(device.handle, &create_info, null, &swapchain));

            var image_count: u32 = 0;
            try mapError(c.vkGetSwapchainImagesKHR(device.handle, swapchain, &image_count, null));
            const images = try allocator.alloc(c.VkImage, image_count);

            try mapError(c.vkGetSwapchainImagesKHR(device.handle, swapchain, &image_count, @ptrCast(images)));

            const image_views = try allocator.alloc(c.VkImageView, image_count);
            for (images, 0..) |image, index| {
                const view_create_info: c.VkImageViewCreateInfo = .{
                    .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                    .image = image,
                    .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                    .format = format.format,
                    .components = .{
                        .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                        .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                        .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                        .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    },
                    .subresourceRange = .{
                        .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                        .baseMipLevel = 0,
                        .levelCount = 1,
                        .baseArrayLayer = 0,
                        .layerCount = 1,
                    },
                };

                try mapError(c.vkCreateImageView(device.handle, &view_create_info, null, &(image_views[index])));
            }

            const framebuffers = try allocator.alloc(c.VkFramebuffer, image_count);
            for (image_views, 0..) |view, index| {
                const framebuffer_info: c.VkFramebufferCreateInfo = .{
                    .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                    .renderPass = render_pass.handle,
                    .attachmentCount = 1,
                    .pAttachments = &view,
                    .width = extent.width,
                    .height = extent.height,
                    .layers = 1,
                };

                try mapError(c.vkCreateFramebuffer(device.handle, &framebuffer_info, null, &(framebuffers[index])));
            }

            return Self{
                .handle = swapchain,
                .format = format,
                .extent = extent,
                .images = images[0..image_count],
                .image_views = image_views[0..image_count],
                .framebuffers = framebuffers,
                .allocator = allocator,
            };
        }

        pub fn nextImage(self: Self, device: Device(n), frame: usize) !usize {
            std.debug.assert(frame < n);
            var index: u32 = undefined;
            try mapError(c.vkAcquireNextImageKHR(device.handle, self.handle, std.math.maxInt(u64), device.image_available[frame], null, &index));

            return @intCast(index);
        }

        pub fn destroy(self: Self, device: Device(n)) void {
            for (self.image_views) |view| {
                c.vkDestroyImageView(device.handle, view, null);
            }

            for (self.framebuffers) |framebuffer| {
                c.vkDestroyFramebuffer(device.handle, framebuffer, null);
            }

            c.vkDestroySwapchainKHR(device.handle, self.handle, null);

            self.allocator.free(self.images);
            self.allocator.free(self.image_views);
            self.allocator.free(self.framebuffers);
        }
    };
}

pub const Surface = struct {
    handle: c.VkSurfaceKHR,

    pub fn presentModes(self: Surface, allocator: Allocator, device: PhysicalDevice) ![]c.VkPresentModeKHR {
        var mode_count: u32 = 0;
        try mapError(c.vkGetPhysicalDeviceSurfacePresentModesKHR(device.handle, self.handle, &mode_count, null));
        const modes = try allocator.alloc(c.VkPresentModeKHR, mode_count);
        try mapError(c.vkGetPhysicalDeviceSurfacePresentModesKHR(device.handle, self.handle, &mode_count, @ptrCast(modes)));

        return modes[0..mode_count];
    }

    pub fn formats(self: Surface, allocator: Allocator, device: PhysicalDevice) ![]c.VkSurfaceFormatKHR {
        var format_count: u32 = 0;
        try mapError(c.vkGetPhysicalDeviceSurfaceFormatsKHR(device.handle, self.handle, &format_count, null));
        const fmts = try allocator.alloc(c.VkSurfaceFormatKHR, format_count);
        try mapError(c.vkGetPhysicalDeviceSurfaceFormatsKHR(device.handle, self.handle, &format_count, @ptrCast(fmts)));

        return fmts[0..format_count];
    }

    pub fn capabilities(self: Surface, device: PhysicalDevice) !c.VkSurfaceCapabilitiesKHR {
        var caps: c.VkSurfaceCapabilitiesKHR = undefined;
        try mapError(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device.handle, self.handle, &caps));
        return caps;
    }
};

pub fn Device(comptime n: usize) type {
    return struct {
        handle: c.VkDevice,
        graphics_queue: c.VkQueue,
        present_queue: c.VkQueue,
        command_pool: c.VkCommandPool,
        command_buffers: [n]c.VkCommandBuffer,
        image_available: [n]c.VkSemaphore,
        render_finished: [n]c.VkSemaphore,
        in_flight_fence: [n]c.VkFence,
        graphics_family: u32,
        present_family: u32,
        device_properties: c.VkPhysicalDeviceProperties,
        memory_properties: c.VkPhysicalDeviceMemoryProperties,

        const Self = @This();

        pub fn resetCommand(self: Self, frame: usize) !void {
            std.debug.assert(frame < n);
            try mapError(c.vkResetCommandBuffer(self.command_buffers[frame], 0));
        }

        pub fn beginCommand(self: Self, frame: usize) !void {
            std.debug.assert(frame < n);
            const begin_info: c.VkCommandBufferBeginInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            };
            try mapError(c.vkBeginCommandBuffer(self.command_buffers[frame], &begin_info));
        }

        pub fn endCommand(self: Self, frame: usize) !void {
            std.debug.assert(frame < n);
            try mapError(c.vkEndCommandBuffer(self.command_buffers[frame]));
        }

        pub fn beginSingleTimeCommands(self: Self) !c.VkCommandBuffer {
            const command_buffer_info: c.VkCommandBufferAllocateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                .commandPool = self.command_pool,
                .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                .commandBufferCount = 1,
            };

            var command_buffer: c.VkCommandBuffer = undefined;
            try mapError(c.vkAllocateCommandBuffers(self.handle, &command_buffer_info, @ptrCast(&command_buffer)));

            const begin_info: c.VkCommandBufferBeginInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            };

            try mapError(c.vkBeginCommandBuffer(command_buffer, &begin_info));

            return command_buffer;
        }

        pub fn endSingleTimeCommands(self: Self, command_buffer: c.VkCommandBuffer) !void {
            try mapError(c.vkEndCommandBuffer(command_buffer));

            const submit_info: c.VkSubmitInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .commandBufferCount = 1,
                .pCommandBuffers = &command_buffer,
            };

            try mapError(c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, null));
            try mapError(c.vkQueueWaitIdle(self.graphics_queue));
            c.vkFreeCommandBuffers(self.handle, self.command_pool, 1, &command_buffer);
        }

        pub fn copyBufferToImage(self: Self, buffer: Buffer, image: c.VkImage, width: u32, height: u32) !void {
            const command_buffer = try self.beginSingleTimeCommands();

            const region: c.VkBufferImageCopy = .{
                .bufferOffset = 0,
                .bufferRowLength = 0,
                .bufferImageHeight = 0,
                .imageSubresource = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .mipLevel = 0,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
                .imageOffset = .{
                    .x = 0, .y = 0, .z = 0,
                },
                .imageExtent = .{
                    .width = width, .height = height, .depth = 1,
                },
            };

            c.vkCmdCopyBufferToImage(
                command_buffer,
                buffer.handle,
                image,
                c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                1,
                &region
            );

            try self.endSingleTimeCommands(command_buffer);
        }

        pub fn transitionImageLayout(self: Self, image: c.VkImage, format: c.VkFormat, old_layout: c.VkImageLayout, new_layout: c.VkImageLayout) !void {
            _ = format;
            const command_buffer = try self.beginSingleTimeCommands();

            var barrier: c.VkImageMemoryBarrier = .{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                .oldLayout = old_layout,
                .newLayout = new_layout,
                .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
                .image = image,
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
                .srcAccessMask = 0,
                .dstAccessMask = 0,
            };

            var sourceStage: c.VkPipelineStageFlags = undefined;
            var destinationStage: c.VkPipelineStageFlags = undefined;

            if (old_layout == c.VK_IMAGE_LAYOUT_UNDEFINED and new_layout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
                barrier.srcAccessMask = 0;
                barrier.dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;

                sourceStage = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
                destinationStage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
            } else if (old_layout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and new_layout == c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
                barrier.srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
                barrier.dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT;

                sourceStage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
                destinationStage = c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
            } else {
                return error.UnsupportedTransition;
            }

            c.vkCmdPipelineBarrier(
                command_buffer,
                sourceStage,
                destinationStage,
                0,
                0, null,
                0, null,
                1, &barrier
            );

            try self.endSingleTimeCommands(command_buffer);
        }

        

        pub fn draw(self: Self, indices: u32, frame: usize) void {
            std.debug.assert(frame < n);
            c.vkCmdDrawIndexed(self.command_buffers[frame], indices, 1, 0, 0, 0);
        }

        pub fn findMemoryType(self: Self, filter: u32, properties: c.VkMemoryPropertyFlags) error{NoSuitableMemory}!u32 {
            const memory_properties = self.memory_properties;

            for (0..memory_properties.memoryTypeCount) |i| {
                if ((filter & (@as(u32, 1) << @intCast(i))) != 0 and (memory_properties.memoryTypes[i].propertyFlags & properties) == properties) {
                    return @intCast(i);
                }
            }

            return error.NoSuitableMemory;
        }

        pub fn waitFence(self: Self, frame: usize) !void {
            //std.debug.assert(frame < n);
            try mapError(c.vkWaitForFences(self.handle, 1, &self.in_flight_fence[frame], c.VK_TRUE, std.math.maxInt(u64)));
            try mapError(c.vkResetFences(self.handle, 1, &self.in_flight_fence[frame]));
        }

        pub fn waitIdle(self: Self) void {
            const mapErrorRes = mapError(c.vkDeviceWaitIdle(self.handle));
            if (mapErrorRes) {} else |err| {
                std.debug.panic("Vulkan wait idle error: {any}\n", .{err});
            }
        }

        pub fn bindIndexBuffer(self: Self, buffer: Buffer, frame: usize) void {
            std.debug.assert(frame < n);
            c.vkCmdBindIndexBuffer(self.command_buffers[frame], buffer.handle, 0, c.VK_INDEX_TYPE_UINT16);
        }

        pub fn bindVertexBuffer(self: Self, buffer: Buffer, frame: usize) void {
            std.debug.assert(frame < n);
            const offset: u64 = 0;
            c.vkCmdBindVertexBuffers(self.command_buffers[frame], 0, 1, &buffer.handle, &offset);
        }

        pub fn bindDescriptorSets(self: Self, pipeline: GraphicsPipeline(n), frame: usize, texture: usize) void {
            const sets = [_]c.VkDescriptorSet {pipeline.descriptor_set, pipeline.textures.items[texture]};
            c.vkCmdBindDescriptorSets(self.command_buffers[frame], c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout, 0, 2, sets[0..].ptr, 0, null);
        }

        pub fn updateBuffer(self: Self, comptime T: type, buffer: Buffer, data: [*]T, frame: usize) void {
            c.vkCmdUpdateBuffer(self.command_buffers[frame], buffer.handle, 0, @sizeOf(T), @ptrCast(@alignCast(data)));
        }

        pub fn pick_memory_type(self: Self, type_bits: u32, flags: u32) u32 {
            var memory_type_index: u32 = 0;
            for (0..self.memory_properties.memoryTypeCount) |index| {
                const memory_type = self.memory_properties.memoryTypes[index];

                if (((type_bits & (@as(u64, 1) << @intCast(index))) != 0) and (memory_type.propertyFlags & flags) != 0 and (memory_type.propertyFlags & c.VK_MEMORY_PROPERTY_DEVICE_COHERENT_BIT_AMD) == 0) {
                    memory_type_index = @intCast(index);
                }
            }

            return memory_type_index;
        }

        pub fn createBuffer(self: Self, usage: BufferUsage, flags: BufferFlags, size: usize) !Buffer {
            const family_indices: []const u32 = &.{self.graphics_family};

            const create_info: c.VkBufferCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .size = size,
                .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
                .usage = @bitCast(usage),
                .queueFamilyIndexCount = 1,
                .pQueueFamilyIndices = family_indices.ptr,
            };

            var buffer: c.VkBuffer = undefined;
            try mapError(c.vkCreateBuffer(self.handle, &create_info, null, &buffer));

            var memory_requirements: c.VkMemoryRequirements = undefined;
            c.vkGetBufferMemoryRequirements(self.handle, buffer, &memory_requirements);

            const alloc_info: c.VkMemoryAllocateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                .allocationSize = memory_requirements.size,
                .memoryTypeIndex = self.pick_memory_type(memory_requirements.memoryTypeBits, @bitCast(flags)),
            };

            var device_memory: c.VkDeviceMemory = undefined;

            try mapError(c.vkAllocateMemory(self.handle, &alloc_info, null, &device_memory));

            try mapError(c.vkBindBufferMemory(self.handle, buffer, device_memory, 0));

            return Buffer{
                .handle = buffer,
                .size = size,
                .memory = device_memory,
            };
        }

        pub fn submit(self: Self, swapchain: Swapchain(n), image: usize, frame: usize) !void {
            std.debug.assert(frame < n);
            const wait_semaphores: [1]c.VkSemaphore = .{self.image_available[frame]};
            const signal_semaphores: [1]c.VkSemaphore = .{self.render_finished[frame]};
            const swapchains: [1]c.VkSwapchainKHR = .{swapchain.handle};
            _ = swapchains;
            const stages: []const u32 = &[_]u32{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};

            const submit_info: c.VkSubmitInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = wait_semaphores[0..].ptr,
                .pWaitDstStageMask = stages.ptr,
                .commandBufferCount = 1,
                .pCommandBuffers = &self.command_buffers[frame],
                .signalSemaphoreCount = 1,
                .pSignalSemaphores = signal_semaphores[0..].ptr,
            };

            _ = c.vkResetFences(self.handle, 1, &self.in_flight_fence[frame]);
            try mapError(c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.in_flight_fence[frame]));

            const present_info: c.VkPresentInfoKHR = .{
                .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = signal_semaphores[0..].ptr,
                .swapchainCount = 1,
                .pSwapchains = &swapchain.handle,
                .pImageIndices = @ptrCast(&image),
                .pResults = null,
            };

            try mapError(c.vkQueuePresentKHR(self.present_queue, &present_info));
        }

        pub fn createShader(self: Self, comptime name: []const u8) !c.VkShaderModule {
            const code = @embedFile(name);

            const create_info: c.VkShaderModuleCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                .codeSize = code.len,
                .pCode = @ptrCast(@alignCast(code)),
            };

            var shader_module: c.VkShaderModule = undefined;

            try mapError(c.vkCreateShaderModule(self.handle, &create_info, null, @ptrCast(&shader_module)));

            return shader_module;
        }

        pub fn destroyShader(self: Self, shader: c.VkShaderModule) void {
            c.vkDestroyShaderModule(self.handle, shader, null);
        }

        pub fn destroy(self: Self) void {
            inline for (0..n) |index| {
                c.vkDestroySemaphore(self.handle, self.image_available[index], null);
                c.vkDestroySemaphore(self.handle, self.render_finished[index], null);
                c.vkDestroyFence(self.handle, self.in_flight_fence[index], null);
            }

            c.vkDestroyCommandPool(self.handle, self.command_pool, null);
            c.vkDestroyDevice(self.handle, null);
        }
    };
}

pub const PhysicalDevice = struct {
    handle: c.VkPhysicalDevice,

    pub fn pick(allocator: Allocator, instance: Instance) !PhysicalDevice {
        var device_count: u32 = 0;
        try mapError(c.vkEnumeratePhysicalDevices(instance.handle, &device_count, null));
        const devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
        defer allocator.free(devices);
        try mapError(c.vkEnumeratePhysicalDevices(instance.handle, &device_count, @ptrCast(devices)));

        return PhysicalDevice{ .handle = devices[0] };
    }

    pub fn queueFamilyProperties(self: PhysicalDevice, allocator: Allocator) ![]const c.VkQueueFamilyProperties {
        var count: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties(self.handle, &count, null);
        const family_properties = try allocator.alloc(c.VkQueueFamilyProperties, count);
        c.vkGetPhysicalDeviceQueueFamilyProperties(self.handle, &count, @ptrCast(family_properties));

        return family_properties;
    }

    pub fn graphicsQueue(self: PhysicalDevice, allocator: Allocator) !u32 {
        const queue_families = try self.queueFamilyProperties(allocator);
        defer allocator.free(queue_families);
        var graphics_queue: ?u32 = null;

        for (queue_families, 0..) |family, index| {
            if (graphics_queue) |_| {
                break;
            }

            if ((family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0x0) {
                graphics_queue = @intCast(index);
            }
        }

        return graphics_queue.?;
    }

    

    pub fn presentQueue(self: PhysicalDevice, surface: Surface, allocator: Allocator) !u32 {
        const queue_families = try self.queueFamilyProperties(allocator);
        defer allocator.free(queue_families);
        var present_queue: ?u32 = null;

        for (queue_families, 0..) |_, index| {
            if (present_queue) |_| {
                break;
            }

            var support: u32 = undefined;
            try mapError(c.vkGetPhysicalDeviceSurfaceSupportKHR(self.handle, @intCast(index), surface.handle, &support));

            if (support == c.VK_TRUE) {
                present_queue = @intCast(index);
            }
        }

        return present_queue.?;
    }

    pub fn create_device(self: *PhysicalDevice, surface: Surface, allocator: Allocator, comptime n: usize) !Device(n) {
        const graphics_queue_index = try self.graphicsQueue(allocator);
        const present_queue_index = try self.presentQueue(surface, allocator);

        const priorities: f32 = 1.0;

        const graphics_queue_info: c.VkDeviceQueueCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = graphics_queue_index,
            .queueCount = 1,
            .pQueuePriorities = &priorities,
        };

        const present_queue_info: c.VkDeviceQueueCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = present_queue_index,
            .queueCount = 1,
            .pQueuePriorities = &priorities,
        };

        const queues: []const c.VkDeviceQueueCreateInfo = &.{ graphics_queue_info, present_queue_info };

        var device_features: c.VkPhysicalDeviceFeatures2 = .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
        };

        c.vkGetPhysicalDeviceFeatures2(self.handle, &device_features);

        const device_info: c.VkDeviceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = &device_features,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = queues.ptr,
            .enabledLayerCount = 0,
            .enabledExtensionCount = @intCast(device_extensions.len),
            .ppEnabledExtensionNames = device_extensions.ptr,
        };

        var device: c.VkDevice = undefined;
        try mapError(c.vkCreateDevice(self.handle, &device_info, null, &device));

        var graphics_queue: c.VkQueue = undefined;
        var present_queue: c.VkQueue = undefined;

        c.vkGetDeviceQueue(device, graphics_queue_index, 0, &graphics_queue);
        c.vkGetDeviceQueue(device, present_queue_index, 0, &present_queue);

        const command_pool_info: c.VkCommandPoolCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = graphics_queue_index,
        };

        var command_pool: c.VkCommandPool = undefined;
        try mapError(c.vkCreateCommandPool(device, &command_pool_info, null, &command_pool));

        const command_buffer_info: c.VkCommandBufferAllocateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = n,
        };

        var command_buffers: [n]c.VkCommandBuffer = undefined;
        try mapError(c.vkAllocateCommandBuffers(device, &command_buffer_info, command_buffers[0..n].ptr));

        const semaphore_info: c.VkSemaphoreCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        const fence_info: c.VkFenceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        var image_available: [n]c.VkSemaphore = undefined;
        var render_finished: [n]c.VkSemaphore = undefined;
        var in_flight_fence: [n]c.VkFence = undefined;

        inline for (0..n) |index| {
            try mapError(c.vkCreateSemaphore(device, &semaphore_info, null, &image_available[index]));
            try mapError(c.vkCreateSemaphore(device, &semaphore_info, null, &render_finished[index]));
            try mapError(c.vkCreateFence(device, &fence_info, null, &in_flight_fence[index]));
        }

        var memory_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
        c.vkGetPhysicalDeviceMemoryProperties(self.handle, &memory_properties);

        var device_properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(self.handle, &device_properties);

        return Device(n){
            .handle = device,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
            .command_pool = command_pool,
            .command_buffers = command_buffers,
            .image_available = image_available,
            .render_finished = render_finished,
            .in_flight_fence = in_flight_fence,
            .graphics_family = graphics_queue_index,
            .present_family = present_queue_index,
            .memory_properties = memory_properties,
            .device_properties = device_properties,
        };
    }
};
