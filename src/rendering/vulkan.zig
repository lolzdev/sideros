pub const Texture = @import("Texture.zig");
pub const GraphicsPipeline = @import("GraphicsPipeline.zig");
pub const Device = @import("Device.zig");
pub const Swapchain = @import("Swapchain.zig");
pub const PhysicalDevice = @import("PhysicalDevice.zig");

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


pub const Error = error{
    out_of_host_memory,
    out_of_device_memory,
    initialization_failed,
    layer_not_present,
    extension_not_present,
    incompatible_driver,
    unknown_error,
};

pub const frames_in_flight = 2;

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

    pub fn deinit(self: Buffer, device_handle: c.VkDevice) void {
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

pub const RenderPass = struct {
    handle: c.VkRenderPass,

    const Self = @This();

    pub fn init(allocator: Allocator, device: Device, surface: Surface, physical_device: PhysicalDevice) !Self {
        const color_attachment: c.VkAttachmentDescription = .{
            .format = (try Swapchain.pickFormat(allocator, surface, physical_device)).format,
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

    pub fn begin(self: Self, swapchain: Swapchain, device: Device, image: usize, frame: usize) void {
        std.debug.assert(frame < frames_in_flight);
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

    pub fn end(self: Self, device: Device, frame: usize) void {
        _ = self;
        std.debug.assert(frame < frames_in_flight);
        c.vkCmdEndRenderPass(device.command_buffers[frame]);
    }

    pub fn deinit(self: Self, device: Device) void {
        c.vkDestroyRenderPass(device.handle, self.handle, null);
    }
};

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
