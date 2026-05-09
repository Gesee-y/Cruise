# Cruise GPU Arrays

Cruise GPU Arryas is a Cruise module designed for GPU-accelerated numerical computations. It is particularly effective when processing massive datasets that require parallelized operations.

Cruise provides an abstract interface to manage GPU memory seamlessly while allowing users to implement and integrate their own GPU backends with ease.

## Features

* **GPU Move Semantics**: Leverages Nim’s hooks (destructors and move semantics) to ensure GPU data is strictly freed only when it is no longer in scope.
* **Reference-Counted Memory**: Since GPU memory is not managed by Nim’s default Garbage Collector, Cruise uses reference counting to safely track and automate resource deallocation.
* **Extensible Architecture**: Easily add new hardware support by defining your custom GPU type and overloading a few core functions.
* **CPU Fallback**: Includes a built-in CPU implementation for logic testing, debugging, or maintaining portability on systems without a dedicated GPU.
* **OpenCL Backend**: Built-in support for OpenCL (standard in most drivers; requires the OpenCL ICD Loader/`opencl.dll`) to offload computations to the GPU.

## Quick Start

### CPU Backend

The CPU backend allows you to run the same logic on your processor for debugging or fallback purposes.

```nim
# Initialize memory to 0
let a = newCPUSeq[float32](3) 
let b = newCPUSeq[float32](3) 

# Create a new GPU-compatible sequence from an existing Nim seq
let c = toGPU[CPUSData[float32], float32](@[1'f32, 2'f32, 3'f32]) 

# Perform element-wise addition and return a new sequence
let d = a + b + c 
echo d.toSeq

```

### OpenCL (CL) Backend

The OpenCL backend moves the execution to the GPU for massive parallelism.

```nim
# Initialize GPU memory to 0
let a = newCLSeq[float32](3) 
let b = newCLSeq[float32](3) 

# Transfer data from CPU to GPU
let c = toGPU[CLSData[float32], float32](@[1'f32, 2'f32, 3'f32]) 

# Perform element-wise addition directly on the GPU device
let d = a + b + c 

# Transfer result back from GPU to CPU for display
echo d.toSeq 

```

### Performance Insights

Based on benchmarks (in the benchmark folder, feel free to run them) on a Core i7 vs AMD FirePro 4190:

* **Massive Speedups on Complex Math**: Up to **48x faster** for exponential and trigonometric functions on large datasets ($n > 10^7$).
* **Memory Management Matters**: Using in-place operations or buffer reuse (the `into` pattern) can make your code **10x faster** by avoiding costly GPU memory allocations.
* **Threshold**: For simple additions, the GPU becomes efficient starting from approximately **250,000 elements**. Below that, the CPU fallback is usually faster due to overhead. 

## Limitations

* **Avoid Random Access**: Accessing individual elements within a GPU array is expensive as it requires synchronizing data back to the CPU. Prefer bulk operations.
* **Dataset Size**: Due to the overhead of memory transfer between Host (CPU) and Device (GPU), Cruise GPU Arrays is not recommended for processing very small datasets where the transfer time might exceed the computation time.
