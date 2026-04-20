# Platform Layer

The platform layer creates a native window, creates the Vulkan instance and
surface, polls native events, and calls the engine C/Zig ABI.

It must not own gameplay state.

## Engine ABI

The shared ABI is declared in `src/sideros_api.h` and implemented/exported by
`src/sideros.zig`.

The important calls are:

- `sideros_init`: initialize engine resources from a Vulkan instance and surface.
- `sideros_update`: tick the engine once.
- `sideros_cleanup`: release engine resources.
- `sideros_key_callback`: update keyboard state.
- `sideros_cursor_callback`: update cursor position.
- `sideros_mouse_button_callback`: update mouse button state.
- `sideros_scroll_callback`: dispatch scroll hooks.
- `sideros_resize_callback`: request renderer resize.

## macOS

Files:

- `src/macos.zig`
- `src/window.m`

`macos.zig` creates the Vulkan instance and Metal surface, calls
`sideros_init`, and runs the frame loop:

```text
poll_cocoa_events()
sideros_update()
```

`window.m` owns the Cocoa `NSWindow` and `NSView`.  It forwards keyboard,
mouse, scroll, and resize events to the engine ABI.

Coordinates sent through `sideros_cursor_callback` are in drawable pixel space
with origin at the top-left of the drawable.

## X11

File:

- `src/xorg.zig`

The X11 path uses XCB.  It creates a window, registers keyboard, button,
motion, scroll, configure, and close events, then calls `sideros_update` once
per loop iteration.

Mouse buttons are mapped to engine buttons:

- X11 button 1: left.
- X11 button 2: middle.
- X11 button 3: right.
- X11 buttons 4/5: scroll.

## Wayland

File:

- `src/wayland.zig`

The Wayland path creates a compositor surface, xdg surface/toplevel, keyboard
listener, pointer listener, and frame callback.

Wayland calls `sideros_update` from the frame callback path.  Pointer motion,
button, and axis events are forwarded through the engine ABI.

## Resize

Platform resize events call `sideros_resize_callback`.  The renderer does not
recreate the swapchain immediately inside the callback.  It stores a pending
extent, then applies the resize at the beginning of a render frame.

