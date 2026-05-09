## Cruise GPU Arrays

This modules allows the user to do calculations on GPU. THis is useful when you have an huge amount of data requiring the same operations.
Cruise offers an abstract interface that manage GPU memory and allows the user to add their owns GPU backend easily.

## Features

- **GPU Move semantics**: This ensure that your GPU data are truly freed only when they are no more necessary using Nim's hooks
- **Refcounted GPU memory**: Since GPU memory are not handled by Nim's GC, Cruise use ref counting to tell you when you should free your data
- **Easy to extend**: You just have to create your gpu type and overload basic functions
- **CPU fallback**: Cruise offers a simple CPU implementation to let you test your logics on CPU (or allows better portability if there is no GPU)
- **OpenCL backend**: This use openCL (mostly provided with your driver, but if not present you will have to download openCL.dll, the ICD Loader), to move your computations to GPU

## Quick start

### CPU Backend
```nim
let a = newCPUSeq[float32](3) # init memory to 0
let b = newCPUSeq[float32](3) # init memory to 0
let c - toGPU[CPUSData[float32], float32](@[1'f32, 2'f32, 3'f32]) # Create a new CLSeq from an initial seq

let d = a + b + c # Create a new CLSeq with the result of this calculation element wise
echo d.toSeq
```

### CL Backend
```nim
let a = newCLSeq[float32](3) # init memory to 0
let b = newCLSeq[float32](3) # init memory to 0
let c - toGPU[CLSData[float32], float32](@[1'f32, 2'f32, 3'f32]) # Create a new CLSeq from an initial seq

let d = a + b + c # Create a new CLSeq with the result of this calculation element wise
echo d.toSeq # Get the data from GPU to CPU
```

## Limitations

- You should avoid random access on GPU Arrays as this would requires the GPU data to go back to CPU, which is expensive.
