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
