const std = @import("std");
const Allocator = std.mem.Allocator;
const components = @import("components.zig");
const sparse = @import("sparse.zig");
const Renderer = @import("renderer");

pub const System = *const fn (*Pool) void;
pub const SystemGroup = []const System;

pub const Resources = struct {
    window: Renderer.Window,
    renderer: Renderer,
};

pub const Pool = struct {
    // Components
    position: sparse.SparseSet(components.Position),
    speed: sparse.SparseSet(components.Speed),
    resources: Resources,
    system_groups: std.ArrayList(SystemGroup),
    thread_pool: *std.Thread.Pool,
    wait_group: std.Thread.WaitGroup,
    mutex: std.Thread.Mutex,
    last_entity: usize,
    free_ids: std.ArrayList(usize),

    component_flags: std.AutoHashMap(usize, usize),

    pub fn init(allocator: Allocator, resources: Resources) !@This() {
        var pool = @This(){
            .position = sparse.SparseSet(components.Position).init(allocator),
            .speed = sparse.SparseSet(components.Speed).init(allocator),
            .resources = resources,
            .system_groups = std.ArrayList(SystemGroup).init(allocator),
            .thread_pool = try allocator.create(std.Thread.Pool),
            .wait_group = .{},
            .mutex = .{},
            .last_entity = 0,
            .free_ids = std.ArrayList(usize).init(allocator),
            .component_flags = std.AutoHashMap(usize, usize).init(allocator),
        };

        try pool.thread_pool.init(.{
            .allocator = allocator,
            .n_jobs = 4,
        });

        return pool;
    }

    pub fn getQuery(self: *@This(), comptime T: type) []T {
        const set = switch (T) {
            components.Speed => &self.speed,
            components.Position => &self.position,
            else => unreachable,
        };

        return set.components.items;
    }

    pub fn getEntity(self: *@This(), component: usize, comptime T: type) usize {
        const set = switch (T) {
            components.Speed => &self.speed,
            components.Position => &self.position,
            else => unreachable,
        };

        return set.dense.items[component];
    }

    pub fn getComponent(self: *@This(), entity: usize, comptime T: type) ?T {
        const set = switch (T) {
            components.Speed => &self.speed,
            components.Position => &self.position,
            else => unreachable,
        };

        if (self.hasComponent(entity, T)) {
            return set.components.items[set.sparse.items[entity]];
        } else {
            return null;
        }
    }

    pub fn hasComponent(self: *@This(), entity: usize, component: type) bool {
        const set = switch (component) {
            components.Speed => &self.speed,
            components.Position => &self.position,
            else => unreachable,
        };

        return set.dense.items[set.sparse.items[entity]] == entity;
    }

    pub fn addSystemGroup(self: *@This(), group: SystemGroup) !void {
        try self.system_groups.append(group);
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        self.position.deinit();
        self.speed.deinit();

        self.system_groups.deinit();
        self.thread_pool.deinit();
        allocator.destroy(self.thread_pool);
        self.free_ids.deinit();
        self.component_flags.deinit();
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

    pub fn createEntity(self: *@This()) !usize {
        const id = self.free_ids.pop() orelse self.last_entity;
        self.last_entity += 1;
        try self.component_flags.put(id, 0x0);

        return id;
    }

    pub fn destroyEntity(self: *@This(), entity: usize) void {
        self.free_ids.append(entity);

        const flags = self.component_flags.get(entity);
        for (0..components.COMPONENT_NUMBER) |i| {
            if (((flags >> i) & 0x1) != 0x0) {
                self.removeComponent(entity, i);
            }
        }
    }

    pub fn addComponent(self: *@This(), entity: usize, component: anytype) !void {
        var set = switch (@TypeOf(component)) {
            components.Speed => &self.speed,
            components.Position => &self.position,
            else => unreachable,
        };

        try self.component_flags.put(entity, self.component_flags.get(entity).? | (0x1 << @TypeOf(component).id));
        try set.addEntity(entity, component);
    }

    pub fn removeComponent(self: *@This(), entity: usize, component_id: usize) void {
        const set = switch (component_id) {
            components.Speed.id => self.speed,
            components.Position.id => self.position,
        };

        self.component_flags.put(entity, self.component_flags.get(entity) & ~(0x1 << component_id));
        set.removeEntity(entity);
    }
};
