const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Position = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Speed = struct {
    speed: f32,
};

pub const Pool = struct {
    comptime sets_map: std.StringHashMap([]const u8) = std.StringHashMap([]const u8).init(allocator),
    speed_set: SparseSet(Speed),
    allocator: Allocator,
    free_ids: std.ArrayList(usize),
    entities: usize,

    pub fn init(allocator: Allocator) !Pool {
        try sets_map.put(@typeName(Speed), "speed_set");

        return Pool{
            .speed_set = try SparseSet(Speed).init(allocator),
            .allocator = allocator,
            .free_ids = try std.ArrayList(usize).initCapacity(allocator, 100),
            .entities = 0,
        };
    }

    pub fn deinit(self: *Pool) void {
        self.sets_map.deinit();
        self.speed_set.deinit();
    }

    pub fn addComponent(self: *Pool, comptime T: type, id: usize, component: T) void {
        var set = @field(self, try self.sets_map.get(@typeName(T)));

        set.insert(id, component);
    }

    pub fn insert(self: *Pool) !usize {
        const id = self.free_ids.pop() orelse self.entities;

        self.entities += 1;
        return id;
    }

    pub fn remove(self: *Pool, id: usize) !usize {
        if (self.speed_set.hasComponent(id)) {
            self.speed_set.remove(id);
        }

        self.entities -= 1;
        self.free_ids.append(id);
    }
};

pub fn SparseSet(comptime T: type) type {
    return struct {
        sparse: std.ArrayList(usize),
        dense: std.ArrayList(usize),
        components: std.ArrayList(T),

        pub fn init(allocator: Allocator) !@This() {
            return @This(){
                .sparse = try std.ArrayList(usize).initCapacity(allocator, 10),
                .dense = try std.ArrayList(usize).initCapacity(allocator, 10),
                .components = try std.ArrayList(T).initCapacity(allocator, 10),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.sparse.deinit();
            self.dense.deinit();
            self.components.deinit();
        }

        pub fn hasComponent(self: *@This(), id: usize) bool {
            return self.dense.items[self.sparse.items[id]] == id;
        }

        pub fn insert(self: *@This(), id: usize, component: T) !void {
            const dense_index = self.dense.items.len;
            try self.dense.append(id);
            try self.components.append(component);
            try self.sparse.append(dense_index);
        }

        pub fn remove(self: *@This(), id: usize) !void {
            const index = self.sparse.items[id];
            const last = self.dense.getLast();
            self.sparse.items[last] = index;
            _ = self.dense.swapRemove(index);
            _ = self.components.swapRemove(index);
        }
    };
}

pub fn test_sparse() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var pool = try Pool.init(allocator);
    defer pool.deinit();

    const entity = try pool.insert();
    std.debug.print("new entity: {d}\n", .{entity});
    pool.addComponent(Speed, entity, .{ .speed = 5.0 });
}
