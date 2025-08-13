const std = @import("std");
const Allocator = std.mem.Allocator;

pub var key: std.ArrayList(ecs.System) = undefined;
pub var scroll: std.ArrayList(ecs.System) = undefined;

pub const Layer = enum {
    key,
    scroll
};

pub fn init(allocator: Allocator) !void {
    key = std.ArrayList(ecs.System).init(allocator);
    scroll = std.ArrayList(ecs.System).init(allocator);
}

pub fn addHook(layer: Layer, hook: ecs.System) !void {
    var list = switch (layer) {
        .key => &key,
        .scroll => &scroll,
    };

    list.append(hook);
}
