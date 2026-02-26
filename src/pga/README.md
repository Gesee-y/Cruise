# Cruise: PGA (Projective Geometric Algebra)

Cruise is one of the few engines that empowers you to use **Projective Geometric Algebra (PGA)** for game development. This provides a unified, lightweight, and high-performance mathematical framework for building games.

### A Unified Mathematical Approach

Instead of juggling disparate concepts like vectors, matrices, and quaternions, PGA uses **multivectors**, versatile objects that can represent geometric entities of any dimension. To keep the learning curve smooth, Cruise introduces intuitive types such as `Point`, `Line`, `Plane`, `Rotor`, and `Motor`.

```nim
import cruise/pga/pga

let p = point2(1, 2)
let m = motor2(PI/2, 3, 5)

// Transformations are as simple as a single multiplication
let transformed_point = m * p

```

## Key Features

* **Performant & Lightweight**: Features optimized structures for every multivector grade, ensuring minimal memory overhead and maximum speed.
* **Strictly Type-Safe**: Leverage Nim’s type system to catch dimensional errors at compile-time rather than runtime.
* **Simplified Transformation Paradigm**: Move beyond complex matrix math; rotations and translations are handled through a single, consistent operation.
* **Numerically Stable**: Inherently avoids common pitfalls like **gimbal lock** and floating-point drift.
* **Superior Interpolation**: Achieve smoother, more natural transitions between transformations compared to traditional linear interpolation.
