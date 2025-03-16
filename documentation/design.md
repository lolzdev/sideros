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

# Gameplay

## Starting
When a new world is created, the players can choose in which biome they want to start their game. Depending on the biome, different resources and thus skills can be acquired.
For example, starting in a forest biome allows the players to gather a lot of woods, which can be traded with other players or used to build structures and tools.
Starting near waters (sea, lakes or rivers) can provide fast way of transportation with boats, fishing and direct access to drinkable water.
Every player starts with a small number of citizens and basic tools.

## Citizens' health
After gathering enough resources, players must ensure that their citizens are happy and healthy: if they start to starve or freeze, they can decide to revolt and unless the player can manage to calm them (using military forces or with an agreement), the game will be over and the player will have to start over.

## Diplomacy
Players can decide to be allied, neutral or enemies with each other and this state can change over the course of the game. By default all the players are neutral.
In case of an attack, players can ask for help to allies whether it's defensive or offensive. State borders are expanded by building structures in neutral territory, or by conquering other states.
When attacking a player, different ways of managing victory can be choosen:
- The defeated player can be taxed by the winner.
- The defeated player can keep independence, but must obey to the winner when receiving orders.
- The defeated player is completely destroyed and must restart the game.
In the first two cases, the winner can keep soldiers on the conquered territory and the defeated can try to revolt against the winner by fighting.

## Attacking

### Military training
Players can choose different ways of training soldiers:
- Every adult male will get at least some basic training and develop fighting skills. You will get a lot of soldiers, but with basic fighting skills.
- A group of regular citizens is selected and trained to develop average fighting skills.
- Specialized soldiers are trained full-time to develop quality fighting skills. In this case soldiers will need to be payed.
Note that enemies can only kill citizens who went through any level of training, otherwise they can only be enslaved. Since the number of slaves a winning player can make in an attack is limited, choosing the second or the third options can assure that at least some citizens will be left.
