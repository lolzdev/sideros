const std = @import("std");
const vk = @import("vulkan.zig");
const c = vk.c;
const Allocator = std.mem.Allocator;
const rendering = @import("rendering.zig");

pub fn DynamicBuffer(comptime T: type) type {
    return struct {
        device: vk.Device,
        usage: vk.BufferUsage,
        flags: vk.BufferFlags,
        handle: c.VkBuffer,
        memory: c.VkDeviceMemory,
        size: usize,
        len: usize,
        element_size: usize,
        free_indices: std.ArrayList(usize),
        allocator: std.mem.Allocator,
        mapped_memory: []T,
        descriptor_set: c.VkDescriptorSet,
        binding: u32,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, device: vk.Device, usage: vk.BufferUsage, flags: vk.BufferFlags, descriptor_set: c.VkDescriptorSet, binding: u32) !Self {
            return initWithCapacity(allocator, device, usage, flags, descriptor_set, binding, 10);
        }

        fn initWithCapacity(allocator: std.mem.Allocator, device: vk.Device, usage: vk.BufferUsage, flags: vk.BufferFlags, descriptor_set: c.VkDescriptorSet, binding: u32, initial_capacity: usize) !Self {
            const size = @sizeOf(T) * initial_capacity;
            const family_indices: []const u32 = &.{device.graphics_family};

            const create_info: c.VkBufferCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .size = size,
                .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
                .usage = @bitCast(usage),
                .queueFamilyIndexCount = 1,
                .pQueueFamilyIndices = family_indices.ptr,
            };

            var buffer: c.VkBuffer = undefined;
            try vk.mapError(c.vkCreateBuffer(device.handle, &create_info, null, &buffer));

            var memory_requirements: c.VkMemoryRequirements = undefined;
            c.vkGetBufferMemoryRequirements(device.handle, buffer, &memory_requirements);

            const alloc_info: c.VkMemoryAllocateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                .allocationSize = memory_requirements.size,
                .memoryTypeIndex = try device.pick_memory_type(memory_requirements.memoryTypeBits, @bitCast(flags)),
            };

            var device_memory: c.VkDeviceMemory = undefined;

            try vk.mapError(c.vkAllocateMemory(device.handle, &alloc_info, null, &device_memory));

            try vk.mapError(c.vkBindBufferMemory(device.handle, buffer, device_memory, 0));

            var mapped_data: [*c]u8 = undefined;

            try vk.mapError(c.vkMapMemory(
                device.handle,
                device_memory,
                0,
                size,
                0,
                @ptrCast(&mapped_data),
            ));

            const mapped_memory: []T = @as([*]T, @ptrCast(@alignCast(mapped_data)))[0..initial_capacity];

            const descriptor_buffer_info = c.VkDescriptorBufferInfo{
                .buffer = buffer,
                .offset = 0,
                .range = size,
            };

            const write_descriptor_set = c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = descriptor_set,
                .dstBinding = binding,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .pBufferInfo = &descriptor_buffer_info,
            };

            c.vkUpdateDescriptorSets(device.handle, 1, &write_descriptor_set, 0, null);

            var free_indices = std.ArrayList(usize).empty;
            for (0..initial_capacity) |i| {
                try free_indices.append(allocator, i);
            }

            return .{
                .handle = buffer,
                .size = size,
                .memory = device_memory,
                .device = device,
                .element_size = @sizeOf(T),
                .usage = usage,
                .flags = flags,
                .allocator = allocator,
                .free_indices = free_indices,
                .mapped_memory = mapped_memory,
                .descriptor_set = descriptor_set,
                .binding = binding,
                .len = 0,
            };
        }

        pub fn elementOffset(self: Self, index: usize) usize {
            return self.element_size * index;
        }

        pub fn items(self: Self) []T {
            return self.mapped_memory[0..self.len];
        }

        pub fn remove(self: *Self, index: usize) !void {
            if (index >= self.mapped_memory.len) {
                return error.IndexOutOfBounds;
            }
            try self.free_indices.append(self.allocator, index);
            if (self.len > 0) {
                self.len -= 1;
            }
            @memset(@as([*]u8, @ptrCast(@alignCast(self.mapped_memory[index..].ptr)))[0..self.element_size], 0);
        }

        pub fn capacity(self: Self) usize {
            return self.mapped_memory.len;
        }

        pub fn ensureCapacity(self: *Self, min_capacity: usize) !void {
            while (self.mapped_memory.len < min_capacity) {
                try self.grow();
            }
        }

        pub fn append(self: *Self, element: T) !void {
            if (self.free_indices.pop()) |index| {
                self.mapped_memory[index] = element;
                self.len += 1;
                return;
            }

            if (self.len >= self.mapped_memory.len) try self.grow();

            self.mapped_memory[self.len] = element;
            self.len += 1;
        }

        pub fn grow(self: *Self) !void {
            const old_capacity = self.mapped_memory.len;
            const new_capacity = old_capacity + (old_capacity / 2) + 1;
            var new = try initWithCapacity(self.allocator, self.device, self.usage, self.flags, self.descriptor_set, self.binding, new_capacity);
            try self.copyTo(new, 0);

            c.vkDestroyBuffer(self.device.handle, self.handle, null);
            c.vkUnmapMemory(self.device.handle, self.memory);
            c.vkFreeMemory(self.device.handle, self.memory, null);

            // Clean up old free_indices and the new buffer's unused free_indices
            const old_free_indices = self.free_indices;
            new.free_indices.deinit(self.allocator);
            self.free_indices = std.ArrayList(usize).empty;
            for (old_free_indices.items) |index| {
                try self.free_indices.append(self.allocator, index);
            }
            // Only add the newly available slots as free (existing data occupies 0..len)
            for (old_capacity..new_capacity) |i| {
                try self.free_indices.append(self.allocator, i);
            }
            old_free_indices.deinit(self.allocator);

            self.size = new.size;
            self.handle = new.handle;
            self.memory = new.memory;
            self.mapped_memory = new.mapped_memory;
        }

        pub fn copyTo(self: Self, dest: Self, offset: usize) !void {
            const command_buffer = try self.device.beginSingleTimeCommands();

            const copy_region: c.VkBufferCopy = .{
                .srcOffset = 0,
                .dstOffset = offset,
                .size = self.size,
            };

            c.vkCmdCopyBuffer(command_buffer, self.handle, dest.handle, 1, &copy_region);

            try self.device.endSingleTimeCommands(command_buffer);
        }

        pub fn deinit(self: *Self) void {
            self.free_indices.deinit(self.allocator);
            c.vkDestroyBuffer(self.device.handle, self.handle, null);
            c.vkUnmapMemory(self.device.handle, self.memory);
            c.vkFreeMemory(self.device.handle, self.memory, null);
        }
    };
}
