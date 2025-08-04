pub const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("xdg-shell.h");
    @cInclude("xcb/xcb.h");
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_wayland.h");
    @cInclude("vulkan/vulkan_xcb.h");
    @cInclude("xcb/xcb_icccm.h");
});
