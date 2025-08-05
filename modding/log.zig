pub extern fn logErr(
    string: *const u8,
    len: u64,
) void;

pub extern fn logWarn(
    string: *const u8,
    len: u64,
) void;

pub extern fn logInfo(
    string: *const u8,
    len: u64,
) void;

pub extern fn logDebug(
    string: *const u8,
    len: u64,
) void;
