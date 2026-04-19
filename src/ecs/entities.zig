const std = @import("std");
const Allocator = std.mem.Allocator;
const components = @import("components.zig");
const sparse = @import("sparse.zig");
const rendering = @import("rendering");
const Renderer = rendering.Renderer;
const Camera = rendering.Camera;
const ecs = @import("ecs.zig");
const Input = ecs.Input;


pub const System = *const fn (*Pool) anyerror!void;
pub const SystemGroup = []const System;
pub const SyncGroup = []const System;

pub const Resources = struct {
    camera: *Camera,
    renderer: *Renderer,
    input: *Input,
    terrain: rendering.Terrain,
    delta_time: f32 = 0.0,
};

pub const Human = struct {
    position: components.Position,
    speed: components.Speed,
};

// TODO(ernesto): Move pool to its own file
pub const Pool = struct {
    humans: std.MultiArrayList(Human),
    resources: *Resources,
    allocator: Allocator,
    system_groups: std.ArrayList(SystemGroup),
    sync_groups: std.ArrayList(SyncGroup),
    threaded_io: std.Io.Threaded,

    pub fn init(allocator: Allocator, resources: *Resources) !@This() {
        const pool = @This(){
            .humans = .{},
            .resources = resources,
            .system_groups = std.ArrayList(SystemGroup).empty,
            .sync_groups = std.ArrayList(SystemGroup).empty,
            .threaded_io = .init(allocator, .{
                .concurrent_limit = .limited(4),
            }),
            .allocator = allocator,
        };

        return pool;
    }

    pub fn addSystemGroup(self: *@This(), group: SystemGroup, sync: bool) !void {
        if (sync) {
            try self.sync_groups.append(self.allocator, group);
        } else {
            try self.system_groups.append(self.allocator, group);
        }
    }

    pub fn deinit(self: *@This()) void {
        self.humans.deinit(self.allocator);

        self.system_groups.deinit(self.allocator);
        self.sync_groups.deinit(self.allocator);
        self.threaded_io.deinit();
    }

    pub fn tick(self: *@This()) !void {
        const io = self.threaded_io.io();
        var group: std.Io.Group = .init;

        for (0..self.system_groups.items.len) |i| {
            group.concurrent(io, struct {
                fn run(pool: *Pool, index: usize) std.Io.Cancelable!void {
                    const system_group = pool.system_groups.items[index];
                    for (system_group) |system| {
                        system(pool) catch |err| std.debug.panic("System execution failed: {any}\n", .{err});
                    }
                }
            }.run, .{ self, i }) catch {
                const system_group = self.system_groups.items[i];
                for (system_group) |system| {
                    system(self) catch |err| std.debug.panic("System execution failed: {any}\n", .{err});
                }
            };
        }
        for (0..self.sync_groups.items.len) |i| {
            const system_group = self.sync_groups.items[i];
            for (system_group) |system| {
                try system(self);
            }
        }

        try group.await(io);
    }

    fn getEntities(self: *@This(), T: type) *std.MultiArrayList(T) {
        return switch (T) {
            Human => &self.humans,
            else => unreachable,
        };
    }

    pub fn createEntity(self: *@This(), entity: anytype) !usize {
        var list = self.getEntities(@TypeOf(entity));
        const index = list.len;
        try list.append(self.allocator, entity);
        return index;
    }

    pub fn destroyEntity(self: *@This(), comptime T: type, entity: usize) void {
        self.getEntities(T).swapRemove(entity);
    }
};
