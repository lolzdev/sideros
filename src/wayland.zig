const c = @import("sideros").c;
const std = @import("std");
const Renderer = @import("sideros").Renderer;
const ecs = @import("sideros").ecs;

var resize = false;
var quit = false;
var new_width: u32 = 0;
var new_height: u32 = 0;

const State = struct {
    compositor: ?*c.wl_compositor = null,
    shell: ?*c.xdg_wm_base = null,
    surface: ?*c.wl_surface = null,
    pool: *ecs.Pool = undefined,
    configured: bool = false,
};

fn registryHandleGlobal(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
    _ = version;
    const state: *State = @alignCast(@ptrCast(data));
    if (std.mem.eql(u8, std.mem.span(interface), std.mem.span(c.wl_compositor_interface.name))) {
        state.compositor = @ptrCast(c.wl_registry_bind(registry.?, name, &c.wl_compositor_interface, 4));
    } else if (std.mem.eql(u8, @as([:0]const u8, std.mem.span(interface)), std.mem.span(c.xdg_wm_base_interface.name))) {
        state.shell = @ptrCast(c.wl_registry_bind(registry.?, name, &c.xdg_wm_base_interface, 4));
        _ = c.xdg_wm_base_add_listener(state.shell, &shell_listener, null);
    }
}

fn registryHandleGlobalRemove(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
}

fn shellHandlePing(data: ?*anyopaque, shell: ?*c.xdg_wm_base, serial: u32) callconv(.c) void {
    _ = data;
    c.xdg_wm_base_pong(shell, serial);
}

fn shellHandleSurfaceConfigure(data: ?*anyopaque, surface: ?*c.xdg_surface, serial: u32) callconv(.c) void {
    const state: *State = @alignCast(@ptrCast(data));

    c.xdg_surface_ack_configure(surface, serial);
    state.configured = true;
}

fn toplevelHandleConfigure(data: ?*anyopaque, toplevel: ?*c.xdg_toplevel, width: i32, height: i32, states: ?*c.wl_array) callconv(.c) void {
    _ = data;
    _ = toplevel;
    _ = states;

    if (width != 0 and height != 0) {
        resize = true;
        new_width = @intCast(width);
        new_height = @intCast(height);
    }
}

fn toplevelHandleClose(data: ?*anyopaque, toplevel: ?*c.xdg_toplevel) callconv(.c) void {
    const state: *State = @alignCast(@ptrCast(data));
    _ = toplevel;

    quit = true;
    state.pool.resources.renderer.deinit();
}

fn toplevelHandleConfigureBounds(data: ?*anyopaque, toplevel: ?*c.xdg_toplevel, width: i32, height: i32) callconv(.c) void {
    _ = data;
    _ = toplevel;
    _ = width;
    _ = height;
}

fn frameHandleDone(data: ?*anyopaque, callback: ?*c.wl_callback, time: u32) callconv(.c) void {
    _ = time;
    const state: *State = @alignCast(@ptrCast(data));
    _ = c.wl_callback_destroy(callback);
    const cb = c.wl_surface_frame(state.surface);
    _ = c.wl_callback_add_listener(cb, &frame_listener, state);

    state.pool.tick();
    _ = c.wl_surface_commit(state.surface);
}

const frame_listener: c.wl_callback_listener = .{
    .done = frameHandleDone,
};

const shell_listener: c.xdg_wm_base_listener = .{
    .ping = shellHandlePing,
};

const surface_listener: c.xdg_surface_listener = .{
    .configure = shellHandleSurfaceConfigure,
};

const toplevel_listener: c.xdg_toplevel_listener = .{
    .configure = toplevelHandleConfigure,
    .configure_bounds = toplevelHandleConfigureBounds,
    .close = toplevelHandleClose,
};

const registry_listener: c.wl_registry_listener = .{
    .global = registryHandleGlobal,
    .global_remove = registryHandleGlobalRemove,
};

pub fn init(allocator: std.mem.Allocator, pool: *ecs.Pool) !void {
    var state: State = .{};
    const display = c.wl_display_connect(null);
    defer c.wl_display_disconnect(display);
    if (display == null) {
        return error.ConnectionFailed;
    }

    const registry = c.wl_display_get_registry(display);
    _ = c.wl_registry_add_listener(registry, &registry_listener, @ptrCast(&state));
    _ = c.wl_display_roundtrip(display);

    const surface = c.wl_compositor_create_surface(state.compositor);
    const xdg_surface = c.xdg_wm_base_get_xdg_surface(state.shell, surface);
    _ = c.xdg_surface_add_listener(xdg_surface, &surface_listener, @ptrCast(&state));

    state.surface = surface;

    const toplevel = c.xdg_surface_get_toplevel(xdg_surface);
    _ = c.xdg_toplevel_add_listener(toplevel, &toplevel_listener, @ptrCast(&state));
    const title = [_]u8 {'s', 'i', 'd', 'e', 'r', 'o', 's', 0};
    c.xdg_toplevel_set_title(toplevel, @ptrCast(&title[0]));
    c.xdg_toplevel_set_app_id(toplevel, @ptrCast(&title[0]));
    c.xdg_toplevel_set_min_size(toplevel, 800, 600);
    c.xdg_toplevel_set_max_size(toplevel, 800, 600);
    
    _ = c.wl_surface_commit(surface);

    while (!state.configured) {
        _ = c.wl_display_dispatch(display);
    }

    var renderer = try Renderer.init(@TypeOf(display), @TypeOf(surface), allocator, display, surface);

    pool.resources.renderer = &renderer;
    state.pool = pool;
    pool.tick();

    const cb = c.wl_surface_frame(surface);
    _ = c.wl_callback_add_listener(cb, &frame_listener, @ptrCast(&state));
    _ = c.wl_surface_commit(surface);

    while (!quit) {
        _ = c.wl_display_dispatch(display);
    }
}
