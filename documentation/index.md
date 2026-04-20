# Sideros Documentation

This directory documents how the engine is put together.  It is written for
contributors who need to find the right subsystem quickly, understand its
contracts, and make a small change without first reading the whole tree.

Start here:

- [architecture.md](architecture.md): high level process and module layout.
- [build.md](build.md): build targets, generated files, and local tooling.
- [platform.md](platform.md): Cocoa, X11, and Wayland entry points.
- [engine-loop.md](engine-loop.md): initialization, frame update, and cleanup.
- [ecs.md](ecs.md): resources, systems, input, hooks, and entities.
- [rendering.md](rendering.md): Vulkan renderer, pipelines, buffers, textures,
  and frame submission.
- [terrain-and-placement.md](terrain-and-placement.md): terrain generation,
  CPU/GPU height matching, cursor picking, and structure placement.
- [modding-vm.md](modding-vm.md): mod loading, parsing, VM runtime, and sandbox
  boundaries.
- [contributing-guide.md](contributing-guide.md): workflow and expectations for
  patches.

Older extensionless documents are still present:

- [DESIGN](DESIGN): long term design and gameplay notes.
- [STYLE](STYLE): coding style.
- [MODDING](MODDING): external modding page pointer.
- [TODO](TODO): loose tasks.

## Documentation Style

Keep documents close to the code.  Prefer a small document per subsystem over a
large essay.  When behavior changes, update the document in the same patch as
the code change.  Paths in this documentation are repository-relative.

