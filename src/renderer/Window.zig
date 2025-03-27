const c = @import("c.zig");
const std = @import("std");

const Window = @This();

pub const Error = error{
    platform_unavailable,
    platform_error,
};

pub fn getExtensions() [][*c]const u8 {
    var extension_count: u32 = undefined;
    const raw: [*c][*c]const u8 = c.glfwGetRequiredInstanceExtensions(&extension_count);
    const extensions = raw[0..extension_count];

    return extensions;
}

title: []const u8,
width: usize,
height: usize,
raw: *c.GLFWwindow,

pub fn create(width: usize, height: usize, title: []const u8) !Window {
    if (c.glfwInit() != c.GLFW_TRUE) {
        const status = c.glfwGetError(null);

        return switch (status) {
            c.GLFW_PLATFORM_UNAVAILABLE => Error.platform_unavailable,
            c.GLFW_PLATFORM_ERROR => Error.platform_error,
            else => unreachable,
        };
    }

    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    const raw = c.glfwCreateWindow(@intCast(width), @intCast(height), title.ptr, null, null);
    c.glfwShowWindow(raw);

    return Window{
        .title = title,
        .width = width,
        .height = height,
        .raw = raw.?,
    };
}

pub fn shouldClose(self: Window) bool {
    return c.glfwWindowShouldClose(self.raw) == c.GLFW_TRUE;
}

pub fn size(self: Window) struct { usize, usize } {
    var width: u32 = undefined;
    var height: u32 = undefined;

    c.glfwGetFramebufferSize(self.raw, @ptrCast(&width), @ptrCast(&height));

    return .{ @intCast(width), @intCast(height) };
}

pub fn destroy(self: Window) void {
    c.glfwDestroyWindow(self.raw);
    c.glfwTerminate();
}
