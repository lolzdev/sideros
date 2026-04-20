# ECS And Systems

The ECS code lives in `src/ecs`.

Important files:

- `src/ecs/ecs.zig`: public namespace and hook declarations.
- `src/ecs/entities.zig`: pool, resources, system groups, and current entity
  lists.
- `src/ecs/Input.zig`: keyboard, mouse, cursor, and per-frame input state.
- `src/ecs/components.zig`: component declarations.
- `src/systems.zig`: current engine systems.

## Resources

`ecs.Resources` is the shared state passed to systems through the pool.  Current
resources include:

- `camera`,
- `renderer`,
- `input`,
- `terrain`,
- `placement`,
- `delta_time`.

Resources are explicit.  Prefer adding a resource when the state is global to a
world or subsystem.  Prefer adding an entity/component when there may be many
instances of the same game concept.

## Entities

The current entity model is minimal.  `Pool` owns a `MultiArrayList(Human)` and
generic helpers:

- `createEntity`,
- `destroyEntity`,
- `getEntities`.

At the moment, many prototype objects are still stored elsewhere.  For example,
placed structures are committed into `Renderer.transforms`.  That is a rendering
shortcut, not the final shape for gameplay simulation.

## Systems

A system has this signature:

```zig
*const fn (*Pool) anyerror!void
```

Systems are registered in groups.  `Pool.tick` runs asynchronous groups first
and synchronized groups second.  The main game systems are currently registered
as one synchronized group to keep ordering deterministic.

Current systems:

- `updatePlacement`: handles structure placement mode, cursor raycast, and
  committed transforms.
- `render`: draws terrain, committed objects, and placement preview.
- `moveCamera`: applies keyboard movement and yaw orbit controls.
- `endInputFrame`: clears per-frame input edges.
- `zoomCamera`: scroll hook that moves camera along its viewing direction.

## Input

`Input` stores both level state and edge state.

Level state:

- `key_pressed`,
- `mouse_down`,
- cursor position,
- cursor delta.

Edge/queued state:

- `key_pressed_this_frame`,
- `mouse_pressed`,
- `mouse_press_count`.

Mouse press counts exist because platform events can occur between frames and
short clicks should not disappear before the placement system handles them.

Input edges are cleared by `endInputFrame`, not by platform callbacks.

## Hooks

`ecs.hooks` currently supports:

- key hooks,
- scroll hooks.

Scroll is used by camera zoom.  Hooks are appropriate for low-frequency,
event-like behavior.  Continuous simulation should be a system.

