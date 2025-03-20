const std = @import("std");
const Allocator = std.mem.Allocator;
const components = @import("components.zig");
const sparse = @import("sparse.zig");

const System = *const fn (Pool) void;
const SystemGroup = std.ArrayList(System);

//FIXME: for some reason this thing has very weird issues with
//hash maps
pub const Pool = struct {
    // Components
    position: sparse.SparseSet(components.Position),
    speed: sparse.SparseSet(components.Speed),

    system_groups: std.ArrayList(SystemGroup),
    thread_pool: std.Thread.Pool,
    wait_group: std.Thread.WaitGroup,
    mutex: std.Thread.Mutex,
    last_entity: usize,
    free_ids: std.ArrayList(usize),

    component_flags: std.AutoHashMap(u32, usize),

    pub fn init(allocator: Allocator) !@This() {
        var pool = @This(){
            .position = sparse.SparseSet(components.Position).init(allocator),
            .speed = sparse.SparseSet(components.Speed).init(allocator),

            .system_groups = std.ArrayList(SystemGroup).init(allocator),
            .thread_pool = undefined,
            .wait_group = .{},
            .mutex = .{},
            .last_entity = 0,
            .free_ids = std.ArrayList(usize).init(allocator),
            .component_flags = std.AutoHashMap(u32, usize).init(allocator),
        };

        try pool.thread_pool.init(.{
            .allocator = allocator,
            .n_jobs = 4,
        });

        return pool;
    }

    pub fn tick(self: *@This()) void {
        for (self.system_groups) |group| {
            self.thread_pool.spawnWg(&self.wait_group, struct {
                fn run(pool: *Pool) void {
                    for (group) |system| {
                        system(pool);
                    }
                }
            }.run, .{self});
        }
        self.wait_group.wait();
    }

    pub fn createEntity(self: *@This()) !usize {
        const id = self.free_ids.pop() orelse self.last_entity;
        self.last_entity += 1;
        try self.component_flags.put(2, 0x2);

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
            components.Speed => self.speed,
            components.Position => self.position,
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
