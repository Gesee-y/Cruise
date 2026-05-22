# Cruise Todo List, inspired from [Frag](https://codeberg.org/hahaitsfunny/frag)

## Core architecture

* [] Hot-reloadable plugin system: gameplay, examples, and the editor are all shared libraries the engine loads at runtime and rebuilds in place without restarting.
* [] First-class C ABI plugin API — plugins are written in any language that can produce a shared library, not just Nim.
* [] Cross-platform application + windowing layer (macOS arm64 and Linux today; Windows scaffolded).
* [] Fiber-based job system with work-stealing scheduling for parallel task graphs.
* [] Lock-free queues, atomics, and a thread pool used throughout the engine internals.
* [] Virtual file system with mount points, alias resolution, and absolute-path passthrough.
* [] Hot-reloading asset pipeline: live file watching on mount points triggers re-imports of textures, shaders, scenes, etc.
* [] Asynchronous, handle-based asset manager with reference counting and reload notifications.
* [] Project-wide custom allocator routing all Nim allocations through a high-performance heap.
* [] Built-in CPU/GPU profiler integration with zone instrumentation across engine + plugin code.
* [] Live shader hot-reload driven by compiled reflection metadata (pipelines rebuilt at runtime from YAML).
* [] Cross-backend graphics abstraction (Metal / GL / D3D11 / WebGPU) selected per-platform.
* [] In-engine logging, string utilities, temp allocator, pool allocator, and slug/handle primitives shared across plugins.

## Build / dev experience

* [] Single-command build for engine, plugins, examples, and editor; debug and release flavours of each.
* [] Per-example build configs so an individual demo can be rebuilt in isolation.
* [] A growing library of demos (cube, physics, audio, input, GUI, ImGui canvas, debug draw, navigation, spline, jobs, profiler, asset loading, game template).

