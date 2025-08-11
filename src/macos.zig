const std = @import("std");
const sideros = @cImport({
    @cInclude("sideros_api.h");
});

const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_macos.h");
    @cInclude("vulkan/vulkan_metal.h");
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
    extension_not_present,
    incompatible_driver,
    layer_not_present,
    out_of_memory,
    unknown_error,
};

fn mapError(result: c_int) !void {
    return switch (result) {
        c.VK_SUCCESS => {},
        c.VK_ERROR_INITIALIZATION_FAILED => Error.initialization_failed,
        c.VK_ERROR_EXTENSION_NOT_PRESENT => Error.extension_not_present,
        c.VK_ERROR_INCOMPATIBLE_DRIVER => Error.incompatible_driver,
        c.VK_ERROR_LAYER_NOT_PRESENT => Error.layer_not_present,
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => Error.out_of_memory,
        else => Error.unknown_error,
    };
}

extern fn create_window() void;
extern fn poll_cocoa_events() void;
extern fn is_window_closed() bool;
extern fn get_metal_layer() *anyopaque;

fn vulkan_init_instance(allocator: std.mem.Allocator, handle: *c.VkInstance) !void {
    const extensions = [_][*c]const u8{ c.VK_MVK_MACOS_SURFACE_EXTENSION_NAME, c.VK_KHR_SURFACE_EXTENSION_NAME, c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME };

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
        .flags = c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
        .ppEnabledExtensionNames = @ptrCast(extensions[0..]),
        .enabledLayerCount = @intCast(newLayers.items.len),
        .ppEnabledLayerNames = newLayers.items.ptr,
    };

    try mapError(c.vkCreateInstance(&instance_info, null, handle));
}

fn vulkan_init_surface(instance: c.VkInstance, layer: *anyopaque, handle: *c.VkSurfaceKHR) !void {
    const create_info: c.VkMacOSSurfaceCreateInfoMVK = .{
        .sType = c.VK_STRUCTURE_TYPE_MACOS_SURFACE_CREATE_INFO_MVK,
        .pView = layer,
    };
    try mapError(c.vkCreateMacOSSurfaceMVK(instance, &create_info, null, handle));
}

fn vulkan_init(allocator: std.mem.Allocator, layer: *anyopaque) !sideros.GameInit {
    var gameInit: sideros.GameInit = undefined;

    try vulkan_init_instance(allocator, &gameInit.instance);
    try vulkan_init_surface(@ptrCast(gameInit.instance), layer, &gameInit.surface);

    return gameInit;
}

// TODO: actually clean up these
fn vulkan_cleanup(gameInit: sideros.GameInit) void {
    _ = gameInit;
    //c.vkDestroySurfaceKHR(gameInit.instance, gameInit.surface, null);
    //c.vkDestroyInstance(gameInit.instance, null);
}

pub fn main() !void {
    create_window();
    const layer = get_metal_layer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() != .ok) @panic("Memory leaked");

    const gameInit = try vulkan_init(allocator, layer);
    defer vulkan_cleanup(gameInit);

    sideros.sideros_init(gameInit);

    while (!is_window_closed()) {
        poll_cocoa_events();
    }
}
