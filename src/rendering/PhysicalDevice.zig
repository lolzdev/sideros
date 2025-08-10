const std = @import("std");
const Allocator = std.mem.Allocator;
const vk = @import("vulkan.zig");
const c = vk.c;

const PhysicalDevice = @This();

const device_extensions: []const [*c]const u8 = &[_][*c]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

handle: c.VkPhysicalDevice,

pub fn pick(allocator: Allocator, instance: vk.Instance) !PhysicalDevice {
    var device_count: u32 = 0;
    try vk.mapError(c.vkEnumeratePhysicalDevices(instance.handle, &device_count, null));
    const devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
    defer allocator.free(devices);
    try vk.mapError(c.vkEnumeratePhysicalDevices(instance.handle, &device_count, @ptrCast(devices)));

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



pub fn presentQueue(self: PhysicalDevice, surface: vk.Surface, allocator: Allocator) !u32 {
    const queue_families = try self.queueFamilyProperties(allocator);
    defer allocator.free(queue_families);
    var present_queue: ?u32 = null;

    for (queue_families, 0..) |_, index| {
        if (present_queue) |_| {
            break;
        }

        var support: u32 = undefined;
        try vk.mapError(c.vkGetPhysicalDeviceSurfaceSupportKHR(self.handle, @intCast(index), surface.handle, &support));

        if (support == c.VK_TRUE) {
            present_queue = @intCast(index);
        }
    }

    return present_queue.?;
}

pub fn create_device(self: *PhysicalDevice, surface: vk.Surface, allocator: Allocator, comptime n: usize) !vk.Device {
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
    try vk.mapError(c.vkCreateDevice(self.handle, &device_info, null, &device));

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
    try vk.mapError(c.vkCreateCommandPool(device, &command_pool_info, null, &command_pool));

    const command_buffer_info: c.VkCommandBufferAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = n,
    };

    var command_buffers: [n]c.VkCommandBuffer = undefined;
    try vk.mapError(c.vkAllocateCommandBuffers(device, &command_buffer_info, command_buffers[0..n].ptr));

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
        try vk.mapError(c.vkCreateSemaphore(device, &semaphore_info, null, &image_available[index]));
        try vk.mapError(c.vkCreateSemaphore(device, &semaphore_info, null, &render_finished[index]));
        try vk.mapError(c.vkCreateFence(device, &fence_info, null, &in_flight_fence[index]));
    }

    var memory_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(self.handle, &memory_properties);

    var device_properties: c.VkPhysicalDeviceProperties = undefined;
    c.vkGetPhysicalDeviceProperties(self.handle, &device_properties);

    const counts = device_properties.limits.framebufferColorSampleCounts & device_properties.limits.framebufferDepthSampleCounts;
    var msaa_samples = c.VK_SAMPLE_COUNT_1_BIT;
    var samples = @as(usize, 1);
    if ((counts & c.VK_SAMPLE_COUNT_64_BIT) != 0) {
        msaa_samples = c.VK_SAMPLE_COUNT_64_BIT;
        samples = 64;
    } else if ((counts & c.VK_SAMPLE_COUNT_32_BIT) != 0) {
        msaa_samples = c.VK_SAMPLE_COUNT_32_BIT;
        samples = 32;
    } else if ((counts & c.VK_SAMPLE_COUNT_16_BIT) != 0) {
        msaa_samples = c.VK_SAMPLE_COUNT_16_BIT;
        samples = 16;
    } else if ((counts & c.VK_SAMPLE_COUNT_8_BIT) != 0) {
        msaa_samples = c.VK_SAMPLE_COUNT_8_BIT;
        samples = 8;
    } else if ((counts & c.VK_SAMPLE_COUNT_4_BIT) != 0) {
        msaa_samples = c.VK_SAMPLE_COUNT_4_BIT;
        samples = 4;
    } else if ((counts & c.VK_SAMPLE_COUNT_2_BIT) != 0) {
        msaa_samples = c.VK_SAMPLE_COUNT_2_BIT;
        samples = 2;
    }

    std.debug.print("Using {} samples for MSAA\n", .{samples});

    return .{
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
        .msaa_samples = @bitCast(msaa_samples),
    };
}
