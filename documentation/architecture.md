# Architecture

Sideros is split into a small platform executable and an engine library.
The executable owns the operating-system window and Vulkan surface.  The engine
library owns game state, ECS resources, rendering state, terrain, input state,
and mod runtimes.

The important top-level source files are:

- `src/macos.zig`: macOS executable entry point.
- `src/window.m`: Cocoa window and input bridge for macOS.
- `src/xorg.zig`: Linux X11 executable entry point.
- `src/wayland.zig`: Linux Wayland executable entry point.
- `src/sideros.zig`: engine library entry point exported to platform layers.
- `src/sideros_api.h`: C ABI shared by Objective-C/C platform code.
- `src/systems.zig`: engine systems run every tick.
- `src/ecs/`: ECS data structures, resources, hooks, and input.
- `src/rendering/`: Vulkan renderer and rendering resources.
- `src/mods/`: WebAssembly parser, VM, runtime, and host bindings.
- `src/math.zig`: vector, matrix, quaternion, and noise helpers.

## Ownership Model

The platform executable owns:

- process entry,
- window creation,
- native event polling,
- native Vulkan surface creation,
- forwarding input and resize events to the engine.

The engine library owns:

- global allocator,
- ECS pool and resources,
- camera,
- input state,
- placement state,
- renderer,
- terrain,
- loaded mods.

`src/sideros.zig` is the boundary between those worlds.  The platform layer calls:

- `sideros_init`,
- `sideros_update`,
- `sideros_cleanup`,
- input callbacks,
- scroll callbacks,
- resize callbacks.

## Module Layout

`build.zig` creates separate Zig modules:

- `math`: `src/math.zig`.
- `mods`: `src/mods/mods.zig`.
- `rendering`: `src/rendering/rendering.zig`.
- `ecs`: `src/ecs/ecs.zig`.
- `sideros`: `src/sideros.zig`.

The dependencies flow mostly one way:

```text
platform executable
        |
        v
    sideros
   /   |   \
ecs rendering mods
 |      |
 v      v
math  vulkan + math
```

Keep this direction in mind when adding APIs.  Engine gameplay systems should
not reach into platform-specific code.  Platform code should forward events and
surface handles, not game concepts.

## Current State

The current engine is still intentionally direct.  Some systems store data in
renderer-owned arrays for fast prototyping, for example committed structure
transforms live in `Renderer.transforms`.  That is acceptable for narrow
features, but long-lived gameplay state should move into ECS entities or
resources before it becomes shared game logic.

