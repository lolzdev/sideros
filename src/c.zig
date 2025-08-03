pub const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("xdg-shell.h");
});
