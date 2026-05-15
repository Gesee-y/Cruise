# Cruise Shader Transpiler

The Cruise Shader Transpiler is a powerful tool that converts native Nim code into **GLSL 4.3**. By leveraging **Shaderc**, it can further compile shaders into SPIR-V, making them compatible with Vulkan, Metal, and other modern backends.

## Features

* **Nim to GLSL Compilation**: Write your shader logic in Nim and get production-ready GLSL code.
* **Auto-Registration**: Automatically handles uniforms and binding registrations.
* **Recursive Dependency Analysis**: Missing functions and custom types used within your shader are automatically detected and defined in the output.
* **Full Pipeline Support**: Create Vertex, Fragment, Geometry, and Compute shaders using the same syntax.
* **Cross-Platform**: Targets Vulkan, Metal, and more via Shaderc integration.

## Quick Start

```nim
type 
  MyVec2 = object
    x, y: float32
  MyVec4 = object
    x, y, z, w: float32
  MyType = object
    x, y, z, w: float32

# Mapping Nim types to IR built-ins
registerIRType(MyVec2, "vec2")
registerIRType(MyVec4, "vec4")

proc myAdd(a, b: float32): float32 = a + b

proc myFunc(frag: var MyVec4, uv: MyVec2) =
  var t: MyType # This custom type is automatically generated in the IR
  frag.x = uv.x
  frag.y = uv.y
  frag.z = myAdd(uv.x, uv.y) # myAdd is recursively added to the IR source

var ir = compileToIR(myFunc)
let shader = emitGLSL(myFunc)
echo shader
```

## Shader VM

The shader VM is a shader built to interpret other shader. This allows you to play any shader without actually compiling it, the time for the real shader to compile asynchronously and replace the VM.

How does it works ?
It's a mix of static constraint imposed by the shader lang and optimizations.
First building the IR from Nim code (standard, 1:1, just with some rough edges like implicit returns), storing line informations to allow better register allocations.
Then compute liveness for each variable through a simple syntactical analysis, knowing aliasing is impossible in shader, it greatly simplify liveness analysis.
Then registers allocation and optimization following each object liveness. Each type in your shader is assigned a set of register.
