const c = @import("c.zig").c;
const ecs = @import("ecs");
const std = @import("std");

const Window = @This();

pub const Error = error{
    platform_unavailable,
    platform_error,
};

pub fn getExtensions() [][*c]const u8 {
    const raw: [*c][*c]const u8 = .{"VK_KHR_wayland_surface", "VK_KHR_surface"};
    const extensions = raw[0..2];

    return extensions;
}

title: []const u8,
width: usize,
height: usize,
raw: *c.wl_display,

pub fn create(width: usize, height: usize, title: []const u8) !Window {
    const raw = c.wl_display_connect(null);

    return Window{
        .title = title,
        .width = width,
        .height = height,
        .raw = raw.?,
    };
}

pub fn setResources(self: *Window, resources: *ecs.Resources) void {
    c.glfwSetWindowUserPointer(self.raw, resources);
}

pub fn shouldClose(self: Window) bool {
    return c.wl_display_dispatch(self.raw) != -1;
}

pub fn size(self: Window) struct { usize, usize } {
    var width: u32 = undefined;
    var height: u32 = undefined;

    c.glfwGetFramebufferSize(self.raw, @ptrCast(&width), @ptrCast(&height));

    return .{ @intCast(width), @intCast(height) };
}

pub fn destroy(self: Window) void {
    c.wl_display_disconnect(self.raw);
}

pub fn getTime() f64 {
    return c.glfwGetTime();
}

pub fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = scancode;
    _ = mods;
    if (c.glfwGetWindowUserPointer(window)) |r| {
        const resources: *ecs.Resources = @alignCast(@ptrCast(r));
        if (action == c.GLFW_PRESS) {
            resources.input.key_pressed[@intCast(key)] = true;
        } else if (action == c.GLFW_RELEASE) {
            resources.input.key_pressed[@intCast(key)] = false;
        }
    }
}

pub fn cursorCallback(window: ?*c.GLFWwindow, x: f64, y: f64) callconv(.c) void {
    if (c.glfwGetWindowUserPointer(window)) |r| {
        const resources: *ecs.Resources = @alignCast(@ptrCast(r));
        var input = resources.input;

        if (input.mouse_first) {
            input.mouse_x = x;
            input.mouse_y = y;
            input.mouse_first = false;
        }

        input.mouse_delta_x = (x - input.mouse_x);
        input.mouse_delta_y = (y - input.mouse_y);
        input.mouse_x = x;
        input.mouse_y = y;
    }
}
