const std = @import("std");
const Renderer = @import("sideros").Renderer;
const c = @import("sideros").c;

pub fn init(allocator: std.mem.Allocator) !void {
    const connection = c.xcb_connect(null, null);
    defer c.xcb_disconnect(connection);

    const setup = c.xcb_get_setup(connection);
    const iter = c.xcb_setup_roots_iterator(setup);
    const screen = iter.data;

    const mask = c.XCB_CW_EVENT_MASK;
    const value = c.XCB_EVENT_MASK_EXPOSURE;

    const window = c.xcb_generate_id(connection);
    _ = c.xcb_create_window(connection, c.XCB_COPY_FROM_PARENT, window, screen.*.root, 0, 0, 800, 600, 10, c.XCB_WINDOW_CLASS_INPUT_OUTPUT, screen.*.root_visual, mask, &value);

    var hints: c.xcb_size_hints_t = undefined;
    c.xcb_icccm_size_hints_set_min_size(&hints, 800, 600);
    c.xcb_icccm_size_hints_set_max_size(&hints, 800, 600);
    _ = c.xcb_icccm_set_wm_size_hints(connection, window, c.XCB_ATOM_WM_NORMAL_HINTS, &hints);

    _ = c.xcb_map_window(connection, window);

    _ = c.xcb_flush(connection);

    var renderer = try Renderer.init(@TypeOf(connection), @TypeOf(window), allocator, connection, window);
    defer renderer.deinit();

    while (true) {
        if (c.xcb_poll_for_event(connection)) |e| {
            switch (e.*.response_type & ~@as(u32, 0x80)) {
                else => {},
            }
            std.c.free(e);
        }

        try renderer.render();
    }
}
