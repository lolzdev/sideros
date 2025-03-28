const std = @import("std");
const Allocator = std.mem.Allocator;
const components = @import("components.zig");
const sparse = @import("sparse.zig");
const Renderer = @import("renderer");
const Input = @import("sideros").Input;

pub const System = *const fn (*Pool) void;
pub const SystemGroup = []const System;

pub const Resources = struct {
    window: Renderer.Window,
    renderer: Renderer,
    input: Input,
};

pub const Human = struct {
    position: components.Position,
    speed: components.Speed,
};

pub const Pool = struct {
    humans: std.MultiArrayList(Human),
    resources: Resources,
    allocator: Allocator,
    system_groups: std.ArrayList(SystemGroup),
    thread_pool: *std.Thread.Pool,
    wait_group: std.Thread.WaitGroup,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: Allocator, resources: Resources) !@This() {
        var pool = @This(){
            .humans = .{},
            .resources = resources,
            .system_groups = std.ArrayList(SystemGroup).init(allocator),
            .thread_pool = try allocator.create(std.Thread.Pool),
            .wait_group = .{},
            .mutex = .{},
            .allocator = allocator,
        };

        try pool.thread_pool.init(.{
            .allocator = allocator,
            .n_jobs = 4,
        });

        return pool;
    }

    pub fn addSystemGroup(self: *@This(), group: SystemGroup) !void {
        try self.system_groups.append(group);
    }

    pub fn deinit(self: *@This()) void {
        self.humans.deinit(self.allocator);

        self.system_groups.deinit();
        self.thread_pool.deinit();
        self.allocator.destroy(self.thread_pool);
    }

    pub fn tick(self: *@This()) void {
        for (0..self.system_groups.items.len) |i| {
            self.thread_pool.spawnWg(&self.wait_group, struct {
                fn run(pool: *Pool, index: usize) void {
                    const group = pool.system_groups.items[index];
                    for (group) |system| {
                        system(pool);
                    }
                }
            }.run, .{ self, i });
        }
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
