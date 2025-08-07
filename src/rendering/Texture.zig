const Texture = @This();
const vk = @import("vulkan.zig");
const c = vk.c;
pub const stb = @cImport({
    @cInclude("stb_image.h");
});

image: c.VkImage,
image_memory: c.VkDeviceMemory,
image_view: c.VkImageView,

pub fn init(path: [:0]const u8, device: anytype) !Texture {
    var width: i32 = 0;
    var height: i32 = 0;
    var channels: i32 = 0;

    const pixels = stb.stbi_load(path, &width, &height, &channels, stb.STBI_rgb_alpha);
    defer stb.stbi_image_free(pixels);

    const size: c.VkDeviceSize  = @as(u64, @intCast(width)) * @as(u64, @intCast(height)) * 4;
    const image_buffer = try device.initBuffer(vk.BufferUsage{ .transfer_src = true }, vk.BufferFlags{ .host_visible = true, .host_coherent = true }, size);

    const pixel_bytes: [*]u8 = @ptrCast(pixels);
    var image_data: [*c]u8 = undefined;

    try vk.mapError(c.vkMapMemory(
        device.handle,
        image_buffer.memory,
        0,
        image_buffer.size,
        0,
        @ptrCast(&image_data),
    ));

    @memcpy(image_data[0..size], pixel_bytes[0..size]);

    c.vkUnmapMemory(
        device.handle,
        image_buffer.memory,
    );

    const create_info: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .extent = .{
            .width = @intCast(width),
            .height = @intCast(height),
            .depth = 1,
        },
        .mipLevels = 1,
        .arrayLayers = 1,
        .format = c.VK_FORMAT_R8G8B8A8_SRGB,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .usage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
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

    try device.transitionImageLayout(image, c.VK_FORMAT_R8G8B8A8_SRGB, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    try device.copyBufferToImage(image_buffer, image, @intCast(width), @intCast(height));
    try device.transitionImageLayout(image, c.VK_FORMAT_R8G8B8A8_SRGB, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    image_buffer.deinit(device.handle);

    const image_view = try createImageView(device, image, c.VK_FORMAT_R8G8B8A8_SRGB);

    return .{
        .image = image,
        .image_memory = image_memory,
        .image_view = image_view,
    };
}

pub fn deinit(self: Texture, device: vk.Device) void {
    c.vkDestroyImageView(device.handle, self.image_view, null);
    c.vkDestroyImage(device.handle, self.image, null);
    c.vkFreeMemory(device.handle, self.image_memory, null);
}

fn createImageView(device: anytype, image: c.VkImage, format: c.VkFormat) !c.VkImageView {
    const create_info: c.VkImageViewCreateInfo = .{
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

    try vk.mapError(c.vkCreateImageView(device.handle, &create_info, null, &image_view));

    return image_view;
}
