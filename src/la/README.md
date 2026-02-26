# Cruise: Math Library

Cruise provides a **generic mathematics library** designed to work seamlessly with any data structure that satisfies the library's required concepts.

Built with cross-library compatibility in mind, Cruise allows you to use its powerful operations on your own custom types without tedious conversion:

```nim
import cruise/la/LA

type
  MyVec3 = object
    x, y, z: float32

  MyRect2D = object
    x1, x2, y1, y2: float32

let a = MyVec3(x: 1, y: 3, z: 4)
echo a.length  // Works automatically via concepts

let r1 = MyRect2D(x1: 1, x2: 4, y1: 1, y2: 4)
let r2 = MyRect2D(x1: 2, x2: 1, y1: 3, y2: 6)
echo intersection(r1, r2)

```

## Features

* **Zero-Overhead Interoperability**: Compatible with generic vectors and shapes from almost any game development math library in C, C++, or Nim.
* **Comprehensive Linear Algebra**: Full support for matrices and spatial transformations.
* **Geometric Randomization**: Generate random distributions within specific shapes and volumes.
* **Advanced Utilities**: Includes a wide array of interpolation methods (Lerp, Slerp, etc.) and mathematical helper functions.
