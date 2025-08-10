const std = @import("std");
const Allocator = std.mem.Allocator;
const vk = @import("vulkan.zig");
const Texture = vk.Texture;
const c = vk.c;
const frames_in_flight = vk.frames_in_flight;

handle: c.VkSwapchainKHR,
images: []c.VkImage,
image_views: []c.VkImageView,
format: c.VkSurfaceFormatKHR,
extent: c.VkExtent2D,
framebuffers: []c.VkFramebuffer,
color_image: c.VkImage,
color_image_memory: c.VkDeviceMemory,
color_image_view: c.VkImageView,

allocator: Allocator,

const Self = @This();

// TODO: This should not be part of the Swapchain?
pub fn pickFormat(allocator: Allocator, surface: vk.Surface, physical_device: vk.PhysicalDevice) !c.VkSurfaceFormatKHR {
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
pub fn init(allocator: Allocator, surface: vk.Surface, device: vk.Device, physical_device: vk.PhysicalDevice, render_pass: vk.RenderPass) !Self {
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

    try vk.mapError(c.vkCreateSwapchainKHR(device.handle, &create_info, null, &swapchain));

    var image_count: u32 = 0;
    try vk.mapError(c.vkGetSwapchainImagesKHR(device.handle, swapchain, &image_count, null));
    const images = try allocator.alloc(c.VkImage, image_count);

    try vk.mapError(c.vkGetSwapchainImagesKHR(device.handle, swapchain, &image_count, @ptrCast(images)));

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

        try vk.mapError(c.vkCreateImageView(device.handle, &view_create_info, null, &(image_views[index])));
    }

    const color_image, const color_image_view, const color_image_memory = try createColorResources(device, device.msaa_samples, format.format);

    const framebuffers = try allocator.alloc(c.VkFramebuffer, image_count);
    for (image_views, 0..) |view, index| {
        const attachments = &[_]c.VkImageView {color_image_view, render_pass.depth_view, view};
        const framebuffer_info: c.VkFramebufferCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass.handle,
            .attachmentCount = 3,
            .pAttachments = attachments[0..].ptr,
            .width = extent.width,
            .height = extent.height,
            .layers = 1,
        };

        try vk.mapError(c.vkCreateFramebuffer(device.handle, &framebuffer_info, null, &(framebuffers[index])));
    }

    return Self{
        .handle = swapchain,
        .format = format,
        .extent = extent,
        .images = images[0..image_count],
        .image_views = image_views[0..image_count],
        .framebuffers = framebuffers,
        .allocator = allocator,
        .color_image = color_image,
        .color_image_view = color_image_view,
        .color_image_memory = color_image_memory,
    };
}

pub fn nextImage(self: Self, device: vk.Device, frame: usize) !usize {
    std.debug.assert(frame < frames_in_flight);
    var index: u32 = undefined;
    try vk.mapError(c.vkAcquireNextImageKHR(device.handle, self.handle, std.math.maxInt(u64), device.image_available[frame], null, &index));

    return @intCast(index);
}

fn createColorResources(device: vk.Device, samples: c.VkSampleCountFlags, format: c.VkFormat) !struct { c.VkImage, c.VkImageView, c.VkDeviceMemory } {
    const create_info: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .extent = .{
            .width = @intCast(800),
            .height = @intCast(600),
            .depth = 1,
        },
        .mipLevels = 1,
        .arrayLayers = 1,
        .format = format,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .usage = c.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .samples = samples,
        .flags = 0,
    };

    var image: c.VkImage = undefined;
    var image_memory: c.VkDeviceMemory = undefined;
    try vk.mapError(c.vkCreateImage(device.handle, &create_info, null, &image));

    var memory_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(device.handle, image, &memory_requirements);

    const alloc_info: c.VkMemoryAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = memory_requirements.size,
        .memoryTypeIndex = try device.findMemoryType(memory_requirements.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
    };

    try vk.mapError(c.vkAllocateMemory(device.handle, &alloc_info, null, &image_memory));
    try vk.mapError(c.vkBindImageMemory(device.handle, image, image_memory, 0));

    const view_create_info: c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var image_view: c.VkImageView = undefined;

    try vk.mapError(c.vkCreateImageView(device.handle, &view_create_info, null, &image_view));

    return .{ image, image_view, image_memory };
}

pub fn deinit(self: Self, device: vk.Device) void {
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

