const std = @import("std");

pub const Id = u64;

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn contains(self: Rect, point: @Vector(2, f32)) bool {
        return point[0] >= self.x and point[1] >= self.y and point[0] < self.x + self.width and point[1] < self.y + self.height;
    }
};

pub const Color = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const DrawCommand = struct {
    rect: Rect,
    color: Color,
};

pub const Button = struct {
    id: Id,
    rect: Rect,
};

const Style = struct {
    panel: Color = .{ .r = 0.06, .g = 0.07, .b = 0.08, .a = 0.88 },
    button: Color = .{ .r = 0.16, .g = 0.18, .b = 0.20, .a = 0.95 },
    button_hot: Color = .{ .r = 0.24, .g = 0.28, .b = 0.31, .a = 0.98 },
    button_active: Color = .{ .r = 0.10, .g = 0.46, .b = 0.78, .a = 1.0 },
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    draw_list: std.ArrayList(DrawCommand),
    mouse_position: @Vector(2, f32) = .{ 0.0, 0.0 },
    mouse_down: bool = false,
    wants_mouse: bool = false,
    hot: Id = 0,
    active: Id = 0,
    style: Style = .{},

    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .allocator = allocator,
            .draw_list = std.ArrayList(DrawCommand).empty,
        };
    }

    pub fn deinit(self: *Context) void {
        self.draw_list.deinit(self.allocator);
    }

    pub fn beginFrame(self: *Context, mouse_position: @Vector(2, f32), mouse_down: bool) void {
        self.draw_list.clearRetainingCapacity();
        self.mouse_position = mouse_position;
        self.mouse_down = mouse_down;
        self.wants_mouse = false;
        self.hot = 0;
    }

    pub fn endFrame(self: *Context) void {
        if (!self.mouse_down) {
            self.active = 0;
        }
    }

    pub fn id(_: *Context, name: []const u8) Id {
        return std.hash.Wyhash.hash(0, name);
    }

    pub fn panel(self: *Context, panel_rect: Rect) !void {
        try self.rect(panel_rect, self.style.panel);
        if (panel_rect.contains(self.mouse_position)) {
            self.wants_mouse = true;
        }
    }

    pub fn button(self: *Context, options: Button, click_available: bool) !bool {
        const hovered = options.rect.contains(self.mouse_position);
        if (hovered) {
            self.hot = options.id;
            self.wants_mouse = true;
        }

        if (hovered and self.mouse_down) {
            self.active = options.id;
        }

        const clicked = hovered and click_available;
        const color = if (self.active == options.id)
            self.style.button_active
        else if (hovered)
            self.style.button_hot
        else
            self.style.button;

        try self.rect(options.rect, color);
        return clicked;
    }

    pub fn rect(self: *Context, draw_rect: Rect, color: Color) !void {
        try self.draw_list.append(self.allocator, .{
            .rect = draw_rect,
            .color = color,
        });
    }
};
