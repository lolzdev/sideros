# Build And Tooling

Sideros uses Zig's build system.  The build script is `build.zig`.

Common commands:

```sh
zig build
zig build run
zig build docs
```

On Linux, the default executable uses X11.  To build the Wayland executable:

```sh
zig build -Dwayland=true
```

## Build Products

The build creates:

- the `sideros` engine library from `src/sideros.zig`,
- one platform executable for the target OS,
- generated SPIR-V shader files from `assets/shaders/*.vert` and
  `assets/shaders/*.frag`,
- optional Zig documentation through the `docs` step.

## External Tools

Shader compilation requires `glslc`.  Vulkan headers are provided through the
`vulkan_headers` dependency in `build.zig.zon`.

macOS builds link:

- Vulkan,
- Cocoa,
- Metal,
- QuartzCore,
- `src/window.m`.

Linux X11 builds link:

- Vulkan,
- XCB,
- xcb-keysyms,
- xcb-icccm.

Linux Wayland builds link:

- Vulkan,
- wayland-client,
- xkbcommon,
- `ext/xdg-shell.c`.

## Generated Shaders

`compileAllShaders` scans `assets/shaders`.  Each shader is compiled with
`glslc` and then added to the rendering module as an anonymous import.  Renderer
code loads these imports through `Device.initShader`.

When adding a shader:

1. Put the GLSL source in `assets/shaders`.
2. Use `.vert` for vertex shaders and `.frag` for fragment shaders.
3. Refer to the generated module name from renderer code using the pattern
   `<basename>_vert` or `<basename>_frag`.

## Tests

The build file currently defines a `test` step, but the referenced
`src/main.zig` test root does not exist in the current tree.  Treat test
coverage as unfinished until that step is repaired.

