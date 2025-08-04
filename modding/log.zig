pub extern fn logErr(
    format: [*:0]const u8,
    ...,
) void;

pub extern fn logWarn(
    format: [*:0]const u8,
    ...,
) void;

pub extern fn logInfo(
    format: [*:0]const u8,
    ...,
) void;

pub extern fn logDebug(
    format: [*:0]const u8,
    ...,
) void;
