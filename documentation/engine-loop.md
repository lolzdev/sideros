# Engine Loop

The engine entry point is `src/sideros.zig`.

The platform layer owns the native loop and calls the engine once per frame.
The engine frame work is performed by the ECS pool.

## Initialization

`sideros_init` performs these steps:

1. Initialize global resources:
   - camera,
   - renderer pointer slot,
   - input,
   - terrain slot,
   - placement state.
2. Initialize ECS hooks.
3. Register the scroll hook for camera zoom.
4. Initialize the ECS pool.
5. Initialize the Vulkan renderer.
6. Generate terrain and upload its heightmap texture.
7. Attach the terrain heightmap to the terrain pipeline.
8. Register synchronized systems:
   - placement update,
   - rendering,
   - camera movement,
   - input end-of-frame reset.
9. Store the renderer in resources.
10. Run one initial tick.

The initial tick is useful because some GPU buffers and frame state expect one
complete frame path before the platform loop starts.

## Update

`sideros_update` currently ignores the incoming `GameUpdate.dt` and calls:

```zig
pool.tick()
```

Delta time is computed inside `systems.render` from the renderer timestamp and
stored as `resources.delta_time`.

## System Order

The current synchronized group order matters:

```text
updatePlacement
render
moveCamera
endInputFrame
```

Placement sees input from events already polled by the platform layer.  Render
draws using the placement state.  Camera movement applies after rendering.
Input edge state is cleared last.

Changing this order can affect click handling, camera movement feel, and preview
positioning.

## Cleanup

`sideros_cleanup`:

1. Deinitializes loaded mods.
2. Deinitializes the ECS pool.
3. Deinitializes the renderer and terrain.
4. Clears renderer initialization state.
5. Deinitializes hooks.
6. Checks the debug allocator for leaks.

The renderer waits for the device to become idle during shutdown before
destroying Vulkan resources.

