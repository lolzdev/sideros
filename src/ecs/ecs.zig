const std = @import("std");

pub const components = @import("components.zig");
pub const entities = @import("entities.zig");
pub const Input = @import("Input.zig");

pub const SystemError = error{
    fail,
    die,
};

pub const Pool = entities.Pool;
pub const Resources = entities.Resources;
pub const System = *const fn (*Pool) anyerror!void;
pub const SystemGroup = []const System;

pub const hooks = struct {
    pub const Scroll = *const fn (*Pool, direction: Input.ScrollDirection) anyerror!void;
    pub const Key = *const fn (*Pool, key: Input.KeyCode) anyerror!void;

    pub var key: std.ArrayList(Key) = undefined;
    pub var scroll: std.ArrayList(Scroll) = undefined;
    var allocator: std.mem.Allocator = undefined;

    pub const Layer = enum {
        key,
        scroll
    };

    pub fn init(gpa: std.mem.Allocator) !void {
        key = std.ArrayList(Key).empty;
        scroll = std.ArrayList(Scroll).empty;
        allocator = gpa;
    }

    pub fn addHook(comptime layer: Layer, hook: anytype) !void {
        var list = comptime switch (layer) {
            .key => &key,
            .scroll => &scroll,
        };

        try list.append(allocator, hook);
    }
};

