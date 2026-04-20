# Rendering

Rendering code lives in `src/rendering`.

The renderer uses Vulkan.  There is no active OpenGL or Metal renderer backend;
macOS uses Vulkan through a Metal surface.

Important files:

- `Renderer.zig`: top-level renderer state and frame orchestration.
- `Device.zig`: Vulkan device, queues, command buffers, buffer helpers.
- `PhysicalDevice.zig`: physical device selection.
- `Swapchain.zig`: swapchain creation and image acquisition.
- `GraphicsPipeline.zig`: mesh/object pipeline.
- `TerrainPipeline.zig`: terrain pipeline.
- `Terrain.zig`: generated terrain data and GPU buffers.
- `Mesh.zig`: glTF mesh loading helpers and terrain mesh generation.
- `Texture.zig`: image upload and texture creation.
- `dynamic_buffer.zig`: mapped resizable GPU buffer helper.
- `gltf.zig`: glTF parsing.

## Renderer State

`Renderer` owns:

- Vulkan instance and surface wrappers,
- physical device and logical device,
- render pass,
- swapchain,
- object graphics pipeline,
- terrain pipeline,
- current frame index,
- the prototype object mesh,
- committed object transforms,
- pending resize state.

The current object path draws one mesh with many transforms.  Each transform is
written into a storage buffer and selected in the vertex shader with a push
constant.

## Frame Flow

`systems.render` drives rendering:

1. Compute frame delta time.
2. Update camera view data.
3. Ensure transform buffer capacity.
4. `renderer.begin`.
5. Set light count.
6. Bind and draw terrain.
7. Bind object pipeline.
8. Draw committed transforms.
9. Draw placement preview transform.
10. `renderer.end`.

`Renderer.begin` waits on the current frame fence, acquires a swapchain image,
resets and begins the command buffer, begins the render pass, and sets dynamic
viewport/scissor.

`Renderer.end` ends the render pass, ends the command buffer, submits it, and
advances the frame index.

## Pipelines

The object pipeline uses:

- `assets/shaders/shader.vert`,
- `assets/shaders/shader.frag`.

The terrain pipeline uses:

- `assets/shaders/terrain.vert`,
- `assets/shaders/terrain.frag`.

Both pipelines share camera, lighting, and descriptor conventions where
possible.

## Dynamic Buffers

`DynamicBuffer(T)` creates a host-visible mapped Vulkan buffer and updates a
descriptor set binding to point at it.

Growth is conservative:

- wait for device idle,
- allocate a larger buffer,
- update descriptor,
- copy old contents,
- unmap and destroy the old buffer.

Dynamic buffers add transfer source and destination usage flags internally so
growth copies are valid.

The idle wait is simple and safe.  A future high-performance renderer should use
per-frame resources or preallocated arena-sized buffers instead.

## Resize

Resize requests are stored in `Renderer.pending_resize`.  The swapchain is
recreated at the beginning of a frame.  This avoids doing expensive Vulkan work
inside platform callbacks.

