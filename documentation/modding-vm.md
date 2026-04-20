# Modding VM

Modding code lives in `src/mods`.

Important files:

- `mods.zig`: public modding namespace.
- `Parser.zig`: WebAssembly parser.
- `wasm.zig`: WebAssembly types and encoding structures.
- `ir.zig`: intermediate representation.
- `vm.zig`: VM execution.
- `external.zig`: host/external calls.

The design goal is sandboxed mods.  Mods should not directly access engine
memory or the filesystem.  Interaction should go through explicit host APIs.

## Current Loading Path

The mod loading code in `src/sideros.zig` is currently commented out, but it
shows the intended flow:

1. Open `assets/mods`.
2. Find `.tar` files.
3. Extract each mod to a temporary directory.
4. Open `main.wasm`.
5. Parse the module with `mods.Parser`.
6. Create a `mods.GlobalRuntime`.
7. Create a `mods.Runtime`.
8. Call the mod `init` external function.
9. Store runtime metadata in `loadedMods`.

Cleanup calls mod `deinit`, destroys the runtime, frees mod names, and
deinitializes the loaded mod list.

## Runtime Shape

Each loaded mod has:

- a display/name slice,
- a runtime pointer,
- a numeric mod index.

The numeric index is passed to mod initialization and can be used as a stable
handle for engine-side bookkeeping.

## Safety Boundaries

The VM is the safety boundary.  New host APIs should be explicit and narrow.
Avoid exposing raw pointers or filesystem access.  Prefer command-style APIs
that validate arguments before touching engine state.

## Contributor Notes

When changing the VM or parser:

- keep parser errors debuggable,
- avoid panicking on malformed mod input where possible,
- document new host calls,
- keep mod-visible ABI changes versionable,
- add tests once the test harness is repaired.

