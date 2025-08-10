const std = @import("std");
const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("xdg-shell.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_wayland.h");
});
const sideros = @cImport({
    @cInclude("sideros_api.h");
});
const builtin = @import("builtin");
const debug = builtin.mode == .Debug;

var resize = false;
var quit = false;
var new_width: u32 = 0;
var new_height: u32 = 0;

fn mapKeysym(keysym: u32) u32 {
    return switch (keysym) {
        0xffe1 => 340,
        else => keysym,
    };
}

const State = struct {
    compositor: ?*c.wl_compositor = null,
    shell: ?*c.xdg_wm_base = null,
    surface: ?*c.wl_surface = null,
    seat: ?*c.wl_seat = null,
    configured: bool = false,
    xkb_context: ?*c.xkb_context = null,
    xkb_state: ?*c.xkb_state = null,
    allocator: std.mem.Allocator,
};

const validation_layers: []const [*c]const u8 = if (!debug) &[0][*c]const u8{} else &[_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const device_extensions: []const [*c]const u8 = &[_][*c]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const Error = error{
    initialization_failed,
    unknown_error,
};

fn mapError(result: c_int) !void {
    return switch (result) {
        c.VK_SUCCESS => {},
        c.VK_ERROR_INITIALIZATION_FAILED => Error.initialization_failed,
        else => Error.unknown_error,
    };
}

fn vulkan_init_instance(allocator: std.mem.Allocator, handle: *c.VkInstance) !void {
    const extensions = [_][*c]const u8{ c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME, c.VK_KHR_SURFACE_EXTENSION_NAME };

    // Querry avaliable extensions size
    var avaliableExtensionsCount: u32 = 0;
    _ = c.vkEnumerateInstanceExtensionProperties(null, &avaliableExtensionsCount, null);
    // Actually querry avaliable extensions
    const avaliableExtensions = try allocator.alloc(c.VkExtensionProperties, avaliableExtensionsCount);
    defer allocator.free(avaliableExtensions);
    _ = c.vkEnumerateInstanceExtensionProperties(null, &avaliableExtensionsCount, avaliableExtensions.ptr);

    // Check the extensions we want against the extensions the user has
    for (extensions) |need_ext| {
        var found = false;
        const needName = std.mem.sliceTo(need_ext, 0);
        for (avaliableExtensions) |useable_ext| {
            const extensionName = useable_ext.extensionName[0..std.mem.indexOf(u8, &useable_ext.extensionName, &[_]u8{0}).?];

            if (std.mem.eql(u8, needName, extensionName)) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.panic("ERROR: Needed vulkan extension {s} not found\n", .{need_ext});
        }
    }

    // Querry avaliable layers size
    var avaliableLayersCount: u32 = 0;
    _ = c.vkEnumerateInstanceLayerProperties(&avaliableLayersCount, null);
    // Actually querry avaliable layers
    const availableLayers = try allocator.alloc(c.VkLayerProperties, avaliableLayersCount);
    defer allocator.free(availableLayers);
    _ = c.vkEnumerateInstanceLayerProperties(&avaliableLayersCount, availableLayers.ptr);

    // Every layer we do have we add to this list, if we don't have it no worries just print a message and continue
    var newLayers = std.ArrayList([*c]const u8).init(allocator);
    defer newLayers.deinit();
    // Loop over layers we want
    for (validation_layers) |want_layer| {
        var found = false;
        for (availableLayers) |useable_validation| {
            const layer_name: [*c]const u8 = &useable_validation.layerName;
            if (std.mem.eql(u8, std.mem.sliceTo(want_layer, 0), std.mem.sliceTo(layer_name, 0))) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("WARNING: Compiled in debug mode, but wanted validation layer {s} not found.\n", .{want_layer});
            std.debug.print("NOTE: Validation layer will be removed from the wanted validation layers\n", .{});
        } else {
            try newLayers.append(want_layer);
        }
    }

    const app_info: c.VkApplicationInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "sideros",
        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "sideros",
        .apiVersion = c.VK_MAKE_VERSION(1, 3, 0),
    };

    const instance_info: c.VkInstanceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(extensions.len),
        .ppEnabledExtensionNames = @ptrCast(extensions[0..]),
        .enabledLayerCount = @intCast(newLayers.items.len),
        .ppEnabledLayerNames = newLayers.items.ptr,
    };

    try mapError(c.vkCreateInstance(&instance_info, null, handle));
}

fn vulkan_init_surface(instance: c.VkInstance, display: ?*c.wl_display, surface: ?*c.wl_surface, handle: *c.VkSurfaceKHR) !void {
    const create_info: c.VkWaylandSurfaceCreateInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
        .display = display,
        .surface = surface,
    };
    try mapError(c.vkCreateWaylandSurfaceKHR(instance, &create_info, null, handle));
}

fn vulkan_init(allocator: std.mem.Allocator, display: ?*c.wl_display, surface: ?*c.wl_surface) !sideros.GameInit {
    var gameInit: sideros.GameInit = undefined;

    try vulkan_init_instance(allocator, &gameInit.instance);
    // TODO(ernesto): This pointer cast is weird as fuck
    try vulkan_init_surface(@ptrCast(gameInit.instance), display, surface, &gameInit.surface);

    return gameInit;
}

fn vulkan_cleanup(gameInit: sideros.GameInit) void {
    // TODO(ernesto): again this ptr
    //     this can be solved merging the cImports. But that seems uglier to me...
    c.vkDestroySurfaceKHR(@ptrCast(gameInit.instance), @ptrCast(gameInit.surface), null);
    c.vkDestroyInstance(@ptrCast(gameInit.instance), null);
}

fn registryHandleGlobal(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
    _ = version;
    const state: *State = @alignCast(@ptrCast(data));
    if (std.mem.eql(u8, std.mem.span(interface), std.mem.span(c.wl_compositor_interface.name))) {
        state.compositor = @ptrCast(c.wl_registry_bind(registry.?, name, &c.wl_compositor_interface, 4));
    } else if (std.mem.eql(u8, @as([:0]const u8, std.mem.span(interface)), std.mem.span(c.xdg_wm_base_interface.name))) {
        state.shell = @ptrCast(c.wl_registry_bind(registry.?, name, &c.xdg_wm_base_interface, 4));
        _ = c.xdg_wm_base_add_listener(state.shell, &shell_listener, null);
    } else if (std.mem.eql(u8, @as([:0]const u8, std.mem.span(interface)), std.mem.span(c.wl_seat_interface.name))) {
        state.seat = @ptrCast(c.wl_registry_bind(registry.?, name, &c.wl_seat_interface, 4));
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
    _ = data;
    _ = toplevel;

    quit = true;
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

    const gameUpdate: sideros.GameUpdate = undefined;
    sideros.sideros_update(gameUpdate);

    _ = c.wl_surface_commit(state.surface);
}

fn keyboardHandleKeymap(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, format: u32, fd: i32, size: u32) callconv(.c) void {
    _ = keyboard;
    _ = format;

    const state: *State = @alignCast(@ptrCast(data));

    const addr = std.posix.mmap(null, size, std.posix.PROT.READ, std.os.linux.MAP { .TYPE = .PRIVATE }, fd, 0) catch @panic("Can't mmap keymap data");
    const mapped: []u8 = @as([*]u8, @ptrCast(addr))[0..size];

    const keymap = c.xkb_keymap_new_from_string(state.xkb_context, @ptrCast(mapped), c.XKB_KEYMAP_FORMAT_TEXT_V1, c.XKB_KEYMAP_COMPILE_NO_FLAGS);
    state.xkb_state = c.xkb_state_new(keymap);
}

fn keyboardHandleEnter(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, surface: ?*c.wl_surface, keys: ?*c.wl_array) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = serial;
    _ = surface;
    _ = keys;
}

fn keyboardHandleLeave(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, surface: ?*c.wl_surface) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = serial;
    _ = surface;
}

fn keyboardHandleKey(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, time: u32, key: u32, s: u32) callconv(.c) void {
    _ = keyboard;
    _ = serial;
    _ = time;

    const state: *State = @alignCast(@ptrCast(data));

    const keysym = c.xkb_state_key_get_one_sym(state.xkb_state, key+8);
    sideros.sideros_key_callback(mapKeysym(keysym), s == 0);
}

fn keyboardHandleModifiers(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, group: u32) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = serial;
    _ = mods_depressed;
    _ = mods_latched;
    _ = mods_locked;
    _ = group;
}

fn keyboardHandleRepeatInfo(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, rate: i32, delay: i32) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = rate;
    _ = delay;
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

const keyboard_listener: c.wl_keyboard_listener = .{
    .keymap = keyboardHandleKeymap,
    .enter = keyboardHandleEnter,
    .leave = keyboardHandleLeave,
    .key = keyboardHandleKey,
    .modifiers = keyboardHandleModifiers,
    .repeat_info = keyboardHandleRepeatInfo,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() != .ok) @panic("Platform memory leaked");

    var state: State = .{ .allocator = allocator };
    state.xkb_context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    const display = c.wl_display_connect(null);
    defer c.wl_display_disconnect(display);
    if (display == null) {
        return error.ConnectionFailed;
    }

    const registry = c.wl_display_get_registry(display);
    _ = c.wl_registry_add_listener(registry, &registry_listener, @ptrCast(&state));
    _ = c.wl_display_roundtrip(display);

    const keyboard = c.wl_seat_get_keyboard(state.seat);
    _ = c.wl_keyboard_add_listener(keyboard, &keyboard_listener, @ptrCast(&state));

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



    const gameInit = try vulkan_init(allocator, display, surface);
    defer vulkan_cleanup(gameInit);
    sideros.sideros_init(gameInit);

    const cb = c.wl_surface_frame(surface);
    _ = c.wl_callback_add_listener(cb, &frame_listener, @ptrCast(&state));
    _ = c.wl_surface_commit(surface);

    while (!quit) {
        _ = c.wl_display_dispatch(display);
    }
}
