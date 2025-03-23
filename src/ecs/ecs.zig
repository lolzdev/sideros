pub const components = @import("components.zig");
const entities = @import("entities.zig");

pub const Pool = entities.Pool;
pub const System = *const fn (*Pool) void;
pub const SystemGroup = []const System;
