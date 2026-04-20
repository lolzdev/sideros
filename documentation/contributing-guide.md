# Contributing Guide

This document complements `documentation/CONTRIBUTING` and `documentation/STYLE`.

## Before Changing Code

Identify the subsystem you are changing:

- platform/windowing: read [platform.md](platform.md),
- frame flow: read [engine-loop.md](engine-loop.md),
- ECS/game state: read [ecs.md](ecs.md),
- rendering/Vulkan: read [rendering.md](rendering.md),
- terrain/placement: read [terrain-and-placement.md](terrain-and-placement.md),
- mods/VM: read [modding-vm.md](modding-vm.md).

Prefer local patterns over new abstractions.  The engine is still small, and
premature architecture can make it harder to see the actual data flow.

## Patch Scope

Keep patches focused.  A good patch usually does one of these:

- fixes one bug,
- adds one small feature,
- refactors one subsystem boundary,
- updates documentation for one behavior change.

Avoid mixing formatting-only changes with behavior changes.

## Verification

At minimum, run:

```sh
zig build
```

When changing Zig files, run `zig fmt` on the files you touched.

If you touch shaders, make sure `zig build` recompiles them successfully.

If you touch platform code, test the relevant platform path when possible:

- macOS: Cocoa/Metal surface path,
- Linux X11: default Linux path,
- Linux Wayland: `zig build -Dwayland=true`.

## Documentation Updates

Update documentation in the same patch when you change:

- subsystem ownership,
- public interfaces,
- frame/system order,
- input semantics,
- Vulkan resource lifetime,
- terrain height math,
- mod ABI or host calls.

Documentation should explain contracts and invariants, not narrate every line of
code.

## Submitting Patches

The existing contribution flow uses email patches:

```sh
git format-patch -M origin/master
git send-email *.patch
```

Before sending, inspect the patch and make sure it does not include unrelated
local changes.

