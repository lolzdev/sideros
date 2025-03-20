const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn SparseSet(comptime T: type) type {
    return struct {
        sparse: std.ArrayList(usize),
        dense: std.ArrayList(usize),
        components: std.ArrayList(T),

        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .sparse = std.ArrayList(usize).init(allocator),
                .dense = std.ArrayList(usize).init(allocator),
                .components = std.ArrayList(T).init(allocator),
            };
        }

        pub fn addEntity(self: *@This(), entity: usize, component: T) !void {
            if (entity >= self.sparse.items.len) {
                try self.sparse.resize(entity + 10);
            }

            self.sparse.items[entity] = self.dense.items.len;
            try self.dense.append(entity);
            try self.components.append(component);
        }

        pub fn removeEntity(self: *@This(), entity: usize) void {
            const last_index = self.dense.getLast();
            const dense_index = self.sparse.items[entity];
            self.dense.swapRemove(dense_index);
            self.components.swapRemove(dense_index);
            self.sparse.items[last_index] = dense_index;
        }
    };
}
