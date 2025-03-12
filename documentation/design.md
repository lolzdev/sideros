# Design
This document contains all the design decisions and features that are and will be implemented in the game.

# Engine
## Rendering
The game engine uses Vulkan as the default graphics API but also implements an OpenGL backend for compatibility with older devices (some of them, while having Vulkan support, have better performance with OpenGL).
An abstraction over the graphics API allows clean utilization of the renderer in the engine, but also exposes a simple interface for mods.
glTF models are used for assets, but once loaded as the game starts, they are going to be converted to an internal intermediate representation format to increase loading performance.
A Metal backend might be implemented in the future for better MacOS integration.

## Logic
An entity component system (ECS) internal API allows better usage of CPU cache lines while also providing a simple interface for the engine internals and mods.

## OS interactions
The OS APIs are abstracted in a platform agnostic interface, used to make usual OS operations like opening files, creating network sockets, creating windows (X11, Wayland, Win32, Cocoa) and so on.

## Mods
Modding is implemented using a custom Wasm (WebAssembly) virtual machine. The VM makes a sandbox for each mod so that they can't directly interact with each other nor accessing main memory or filesystem.
This safety features allow to download mods bytecode when joining a multiplayer game on the fly without worrying and without needing to install them locally before joining.
While not every language will be supported officaly, community projects can easily implement bindings for the engine modding API and then compile to a Wasm target.