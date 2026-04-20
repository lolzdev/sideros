# Terrain And Structure Placement

Terrain code lives mostly in:

- `src/rendering/Terrain.zig`,
- `src/rendering/Mesh.zig`,
- `assets/shaders/terrain.vert`,
- `assets/shaders/terrain.frag`,
- `src/systems.zig`.

## Terrain Generation

`Terrain.init` generates a normalized heightmap using `math.PerlinNoise.fbm`.
The generator configuration controls:

- octaves,
- lacunarity,
- gain,
- scale,
- multiplier,
- exponent,
- world width and height,
- seed,
- resolution.

The terrain stores:

- `heightmap`: CPU height data,
- `width` and `height`: heightmap dimensions in samples,
- `world_width` and `world_height`: terrain size in world units,
- heightmap texture,
- vertex buffer,
- index buffer.

Heightmap samples are stored row-major:

```text
index = z * width + x
```

Keep CPU terrain sampling, texture upload, and terrain mesh generation aligned
with that convention.

## Terrain Mesh

`Mesh.terrain` creates a regular grid.  The grid has:

- `columns = width * resolution`,
- `rows = height * resolution`.

Vertices are emitted row-major.  Indices are emitted with winding that matches
the terrain pipeline:

```zig
frontFace = VK_FRONT_FACE_CLOCKWISE
cullMode = VK_CULL_MODE_BACK_BIT
```

If the terrain becomes mostly black or disappears after mesh changes, check
triangle winding first.

## GPU Height Formula

The terrain vertex shader samples the heightmap texture:

```glsl
float y = texture(diffuseSampler, uv).x;
float mul = pow(2, y * 5);
world_y = y * mul;
```

CPU picking must match this formula or placement will float above or sink below
the rendered terrain.

The current heightmap texture format is `VK_FORMAT_R8G8B8A8_SRGB`.  Therefore
CPU placement code also accounts for 8-bit quantization and sRGB decoding before
applying the shader height formula.

A cleaner future change would be to store heightmaps in a linear format, such as
an unsigned normalized or single-channel format, and remove the sRGB conversion
from CPU placement.

## Placement State

Placement state is stored in `ecs.Placement`:

- `active`: placement mode is enabled.
- `preview_valid`: cursor currently has a valid terrain target.
- `preview_position`: ground position under the cursor.
- `preview_scale`: structure preview scale.

`B` toggles placement mode.  `Escape` cancels it.

## Cursor Picking

`systems.updatePlacement` gets cursor position from `Input`, builds a camera ray,
and intersects it with terrain.

Picking steps:

1. Convert cursor pixel coordinates to normalized device coordinates.
2. Build a world-space ray from the camera orientation.
3. Step along the ray until it crosses terrain height.
4. Binary-search the crossing interval.
5. Store the hit as `placement.preview_position`.

The ray center direction is derived from:

```zig
camera.getTarget() - camera.position
```

This matches the current camera convention better than using
`camera.getDirection()` directly after yaw rotation.

## Preview And Commit

Rendering draws:

1. committed object transforms from `Renderer.transforms`,
2. one transient placement preview transform, if valid.

The preview is not appended to `Renderer.transforms`.  It is written into the
transform buffer only for the current draw.

When left click is consumed by placement, a transform is appended to
`Renderer.transforms`.  The current model origin is treated as centered, so the
committed transform is shifted upward by:

```zig
ground_y + scale_y * 0.5
```

This keeps the cube resting on the terrain instead of centered halfway through
it.

## Future Direction

`Renderer.transforms` is not the final storage location for RTS structures.  It
is a prototype path.  Real structures should become ECS/gameplay state, with the
renderer deriving draw transforms from that state.

