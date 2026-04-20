const std = @import("std");
const sideros = @cImport({
    @cInclude("sideros_api.h");
});
const c = @cImport({
    @cInclude("xcb/xcb.h");
    @cInclude("xcb/xcb_keysyms.h");
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_xcb.h");
    @cInclude("xcb/xcb_icccm.h");
});

const builtin = @import("builtin");
const debug = (builtin.mode == .Debug);

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

fn mapKeysym(keysym: u32) u32 {
    return switch (keysym) {
        0xffe1 => 340,
        else => keysym,
    };
}

fn vulkan_init_instance(allocator: std.mem.Allocator, handle: *c.VkInstance) !void {
    const extensions = [_][*c]const u8{ c.VK_KHR_XCB_SURFACE_EXTENSION_NAME, c.VK_KHR_SURFACE_EXTENSION_NAME };

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
    var newLayers = std.ArrayList([*c]const u8).empty;
    defer newLayers.deinit(allocator);
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
            try newLayers.append(allocator, want_layer);
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

fn vulkan_init_surface(instance: c.VkInstance, connection: ?*c.xcb_connection_t, window: u32, handle: *c.VkSurfaceKHR) !void {
    const create_info: c.VkXcbSurfaceCreateInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
        .connection = connection,
        .window = window,
    };
    try mapError(c.vkCreateXcbSurfaceKHR(instance, &create_info, null, handle));
}

fn vulkan_init(allocator: std.mem.Allocator, connection: ?*c.xcb_connection_t, window: u32) !sideros.GameInit {
    var gameInit: sideros.GameInit = undefined;

    try vulkan_init_instance(allocator, &gameInit.instance);
    // TODO(ernesto): This pointer cast is weird as fuck
    try vulkan_init_surface(@ptrCast(gameInit.instance), connection, window, &gameInit.surface);

    return gameInit;
}

fn vulkan_cleanup(gameInit: sideros.GameInit) void {
    c.vkDestroySurfaceKHR(gameInit.instance, gameInit.surface, null);
    c.vkDestroyInstance(gameInit.instance, null);
}

fn internAtom(connection: ?*c.xcb_connection_t, only_if_exists: u8, name: []const u8) !c.xcb_atom_t {
    const cookie = c.xcb_intern_atom(connection, only_if_exists, @intCast(name.len), name.ptr);
    const reply = c.xcb_intern_atom_reply(connection, cookie, null) orelse return error.AtomLookupFailed;
    defer std.c.free(reply);
    return reply.*.atom;
}

pub fn main() !void {
    const connection = c.xcb_connect(null, null);
    defer c.xcb_disconnect(connection);
    const keysyms = c.xcb_key_symbols_alloc(connection);
    defer c.xcb_key_symbols_free(keysyms);

    const setup = c.xcb_get_setup(connection);
    const iter = c.xcb_setup_roots_iterator(setup);
    const screen = iter.data;

    const mask = c.XCB_CW_EVENT_MASK;
    const value = c.XCB_EVENT_MASK_EXPOSURE | c.XCB_EVENT_MASK_KEY_PRESS | c.XCB_EVENT_MASK_KEY_RELEASE | c.XCB_EVENT_MASK_BUTTON_PRESS | c.XCB_EVENT_MASK_BUTTON_RELEASE | c.XCB_EVENT_MASK_POINTER_MOTION | c.XCB_EVENT_MASK_STRUCTURE_NOTIFY;

    const window = c.xcb_generate_id(connection);
    _ = c.xcb_create_window(connection, c.XCB_COPY_FROM_PARENT, window, screen.*.root, 0, 0, 800, 600, 10, c.XCB_WINDOW_CLASS_INPUT_OUTPUT, screen.*.root_visual, mask, &value);
    const wm_protocols = try internAtom(connection, 0, "WM_PROTOCOLS");
    const wm_delete_window = try internAtom(connection, 0, "WM_DELETE_WINDOW");
    _ = c.xcb_change_property(connection, c.XCB_PROP_MODE_REPLACE, window, wm_protocols, c.XCB_ATOM_ATOM, 32, 1, &wm_delete_window);

    var hints: c.xcb_size_hints_t = undefined;
    c.xcb_icccm_size_hints_set_min_size(&hints, 800, 600);
    _ = c.xcb_icccm_set_wm_size_hints(connection, window, c.XCB_ATOM_WM_NORMAL_HINTS, &hints);

    _ = c.xcb_map_window(connection, window);

    _ = c.xcb_flush(connection);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() != .ok) @panic("Memory leaked");

    const gameInit = try vulkan_init(allocator, connection, window);
    defer vulkan_cleanup(gameInit);

    sideros.sideros_init(gameInit);

    var running = true;
    while (running) {
        if (c.xcb_poll_for_event(connection)) |e| {
            switch (e.*.response_type & ~@as(u32, 0x80)) {
                c.XCB_KEY_PRESS => {
                    const ev: *c.xcb_key_press_event_t = @ptrCast(e);
                    const key = c.xcb_key_symbols_get_keysym(keysyms, ev.detail, 0);
                    sideros.sideros_key_callback(mapKeysym(key), false);
                },
                c.XCB_KEY_RELEASE => {
                    const ev: *c.xcb_key_release_event_t = @ptrCast(e);
                    const key = c.xcb_key_symbols_get_keysym(keysyms, ev.detail, 0);
                    sideros.sideros_key_callback(mapKeysym(key), true);
                },
                c.XCB_BUTTON_PRESS => {
                    const ev: *c.xcb_button_press_event_t = @ptrCast(e);
                    sideros.sideros_cursor_callback(@floatFromInt(ev.event_x), @floatFromInt(ev.event_y));
                    switch (ev.detail) {
                        4 => sideros.sideros_scroll_callback(true),
                        5 => sideros.sideros_scroll_callback(false),
                        1 => sideros.sideros_mouse_button_callback(0, false),
                        2 => sideros.sideros_mouse_button_callback(2, false),
                        3 => sideros.sideros_mouse_button_callback(1, false),
                        else => {},
                    }
                },
                c.XCB_BUTTON_RELEASE => {
                    const ev: *c.xcb_button_release_event_t = @ptrCast(e);
                    sideros.sideros_cursor_callback(@floatFromInt(ev.event_x), @floatFromInt(ev.event_y));
                    switch (ev.detail) {
                        1 => sideros.sideros_mouse_button_callback(0, true),
                        2 => sideros.sideros_mouse_button_callback(2, true),
                        3 => sideros.sideros_mouse_button_callback(1, true),
                        else => {},
                    }
                },
                c.XCB_MOTION_NOTIFY => {
                    const ev: *c.xcb_motion_notify_event_t = @ptrCast(e);
                    sideros.sideros_cursor_callback(@floatFromInt(ev.event_x), @floatFromInt(ev.event_y));
                },
                c.XCB_CONFIGURE_NOTIFY => {
                    const ev: *c.xcb_configure_notify_event_t = @ptrCast(e);
                    sideros.sideros_resize_callback(ev.width, ev.height);
                },
                c.XCB_CLIENT_MESSAGE => {
                    const ev: *c.xcb_client_message_event_t = @ptrCast(e);
                    if (ev.type == wm_protocols and ev.data.data32[0] == wm_delete_window) {
                        running = false;
                    }
                },
                else => {},
            }
            std.c.free(e);
        }
        if (running) {
            const gameUpdate: sideros.GameUpdate = undefined;
            sideros.sideros_update(gameUpdate);
        }
    }

    sideros.sideros_cleanup();
}
