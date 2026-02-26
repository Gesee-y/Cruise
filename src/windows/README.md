# Cruise: Windowing

In modern GUI applications, the ability to switch between multiple windowing APIs (e.g., [SDL2](https://www.libsdl.org), [GLFW](https://www.glfw.org)) while minimizing dependencies on specific libraries is critical.
Cruise offers you a clean abstraction to build your own windowing backend from scratch.
It manages events, logs, input states and queries for you.

## Features  

- **API abstraction**: Unified interface for SDL2, GLFW, and more.  
- **Extensible**: Easily add new windowing APIs via a simple interface.  
- **Event-driven**: Subscribe to events (including API-specific errors) using `Notifier` objects.  
- **Hierarchical windows**: Create subwindows across different APIs.  
- **Unified input handling**: Consistent input management for GLFW, SDL, and others.  

