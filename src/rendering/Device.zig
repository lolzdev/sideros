const std = @import("std");
const vk = @import("vulkan.zig");
const Mesh = @import("Mesh.zig");
const Texture = vk.Texture;
const c = vk.c;
const frames_in_flight = vk.frames_in_flight;

handle: c.VkDevice,
graphics_queue: c.VkQueue,
present_queue: c.VkQueue,
command_pool: c.VkCommandPool,
command_buffers: [frames_in_flight]c.VkCommandBuffer,
image_available: [frames_in_flight]c.VkSemaphore,
render_finished: [frames_in_flight]c.VkSemaphore,
in_flight_fence: [frames_in_flight]c.VkFence,
graphics_family: u32,
present_family: u32,
device_properties: c.VkPhysicalDeviceProperties,
memory_properties: c.VkPhysicalDeviceMemoryProperties,

const Self = @This();

pub fn resetCommand(self: Self, frame: usize) !void {
    std.debug.assert(frame < frames_in_flight);
    try vk.mapError(c.vkResetCommandBuffer(self.command_buffers[frame], 0));
}

pub fn beginCommand(self: Self, frame: usize) !void {
    std.debug.assert(frame < frames_in_flight);
    const begin_info: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try vk.mapError(c.vkBeginCommandBuffer(self.command_buffers[frame], &begin_info));
}

pub fn endCommand(self: Self, frame: usize) !void {
    std.debug.assert(frame < frames_in_flight);
    try vk.mapError(c.vkEndCommandBuffer(self.command_buffers[frame]));
}

pub fn beginSingleTimeCommands(self: Self) !c.VkCommandBuffer {
    const command_buffer_info: c.VkCommandBufferAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = self.command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var command_buffer: c.VkCommandBuffer = undefined;
    try vk.mapError(c.vkAllocateCommandBuffers(self.handle, &command_buffer_info, @ptrCast(&command_buffer)));

    const begin_info: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };

    try vk.mapError(c.vkBeginCommandBuffer(command_buffer, &begin_info));

    return command_buffer;
}

pub fn endSingleTimeCommands(self: Self, command_buffer: c.VkCommandBuffer) !void {
    try vk.mapError(c.vkEndCommandBuffer(command_buffer));

    const submit_info: c.VkSubmitInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,
    };

    try vk.mapError(c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, null));
    try vk.mapError(c.vkQueueWaitIdle(self.graphics_queue));
    c.vkFreeCommandBuffers(self.handle, self.command_pool, 1, &command_buffer);
}

pub fn copyBufferToImage(self: Self, buffer: vk.Buffer, image: c.VkImage, width: u32, height: u32) !void {
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



pub fn draw(self: Self, indices: u32, frame: usize, mesh: Mesh) void {
    std.debug.assert(frame < frames_in_flight);
    c.vkCmdDrawIndexed(self.command_buffers[frame], indices, 1, mesh.index_buffer, mesh.vertex_buffer, 0);
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
    try vk.mapError(c.vkWaitForFences(self.handle, 1, &self.in_flight_fence[frame], c.VK_TRUE, std.math.maxInt(u64)));
    try vk.mapError(c.vkResetFences(self.handle, 1, &self.in_flight_fence[frame]));
}

pub fn waitIdle(self: Self) void {
    const mapErrorRes = vk.mapError(c.vkDeviceWaitIdle(self.handle));
    if (mapErrorRes) {} else |err| {
        std.debug.panic("Vulkan wait idle error: {any}\n", .{err});
    }
}

pub fn bindIndexBuffer(self: Self, buffer: vk.Buffer, frame: usize) void {
    std.debug.assert(frame < frames_in_flight);
    c.vkCmdBindIndexBuffer(self.command_buffers[frame], buffer.handle, 0, c.VK_INDEX_TYPE_UINT16);
}

pub fn bindVertexBuffer(self: Self, buffer: vk.Buffer, frame: usize) void {
    std.debug.assert(frame < frames_in_flight);
    const offset: u64 = 0;
    c.vkCmdBindVertexBuffers(self.command_buffers[frame], 0, 1, &buffer.handle, &offset);
}

pub fn bindDescriptorSets(self: Self, pipeline: vk.GraphicsPipeline, frame: usize, texture: usize) void {
    const sets = [_]c.VkDescriptorSet {pipeline.descriptor_set, pipeline.textures.items[texture]};
    c.vkCmdBindDescriptorSets(self.command_buffers[frame], c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout, 0, 2, sets[0..].ptr, 0, null);
}

pub fn updateBuffer(self: Self, comptime T: type, buffer: vk.Buffer, data: [*]T, frame: usize) void {
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

pub fn initBuffer(self: Self, usage: vk.BufferUsage, flags: vk.BufferFlags, size: usize) !vk.Buffer {
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
    try vk.mapError(c.vkCreateBuffer(self.handle, &create_info, null, &buffer));

    var memory_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(self.handle, buffer, &memory_requirements);

    const alloc_info: c.VkMemoryAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = memory_requirements.size,
        .memoryTypeIndex = self.pick_memory_type(memory_requirements.memoryTypeBits, @bitCast(flags)),
    };

    var device_memory: c.VkDeviceMemory = undefined;

    try vk.mapError(c.vkAllocateMemory(self.handle, &alloc_info, null, &device_memory));

    try vk.mapError(c.vkBindBufferMemory(self.handle, buffer, device_memory, 0));

    return .{
        .handle = buffer,
        .size = size,
        .memory = device_memory,
    };
}

pub fn submit(self: Self, swapchain: vk.Swapchain, image: usize, frame: usize) !void {
    std.debug.assert(frame < frames_in_flight);
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
    try vk.mapError(c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.in_flight_fence[frame]));

    const present_info: c.VkPresentInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = signal_semaphores[0..].ptr,
        .swapchainCount = 1,
        .pSwapchains = &swapchain.handle,
        .pImageIndices = @ptrCast(&image),
        .pResults = null,
    };

    try vk.mapError(c.vkQueuePresentKHR(self.present_queue, &present_info));
}

pub fn initShader(self: Self, comptime name: []const u8) !c.VkShaderModule {
    const code = @embedFile(name);

    const create_info: c.VkShaderModuleCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = @ptrCast(@alignCast(code)),
    };

    var shader_module: c.VkShaderModule = undefined;

    try vk.mapError(c.vkCreateShaderModule(self.handle, &create_info, null, @ptrCast(&shader_module)));

    return shader_module;
}

pub fn deinitShader(self: Self, shader: c.VkShaderModule) void {
    c.vkDestroyShaderModule(self.handle, shader, null);
}

pub fn deinit(self: Self) void {
    inline for (0..frames_in_flight) |index| {
        c.vkDestroySemaphore(self.handle, self.image_available[index], null);
        c.vkDestroySemaphore(self.handle, self.render_finished[index], null);
        c.vkDestroyFence(self.handle, self.in_flight_fence[index], null);
    }

    c.vkDestroyCommandPool(self.handle, self.command_pool, null);
    c.vkDestroyDevice(self.handle, null);
}
