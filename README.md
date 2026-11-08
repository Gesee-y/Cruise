# Cruise Shader VM (CVM/CSVM/SVM, whethever, no one's care :p)

Cruise VM is an implementation of a **Virtual Machine** on top of **Nimony** or **Nim 3**, whethever tf you want to call it.
So what it does is using compiler plugins to turn a module into bytecode.

It also have a few restriction:

- Can't use `ref`
- Can only import some predefined module
- No recursion
- Limited memory and stack size (255 bytes of memory, 64 bytes stack)
- No top level expression

So why should we care about such a restricted VM ?
Because it's made entirely to run on GPU!

## Quick start

In the program to run on the VM, let's name it `mainKernel.nim`:

```nim
import CVM

translateToBytecode()

const N {.uniform.}: int

proc mainKernel(i {.globalIndex.}: int, a {.ssbo.}: seq[int], b {.ssbo.}: seq[int], c {.ssbo.}: var seq[int]):
  if i < N:
    c[i] = a[i] + b[i]
```

This will generate a `mainKernel.cbc` file, which contains the bytecode of the program.

Then in the program running it:

```nim
import CVM

proc main:
  let data = loadBytecode("path/to/mainKernel.cbc")
  var c: seq[int] = @[0, 0, 0]
  runVM(OpenCL, data, (@[1, 2, 3], @[4, 5, 6], c, 3)) # First argument is the bytecode, the remaining are the arguments
```

The VM will first be translated to openCL code, then be fed the bytecode and argument to run.

## Why this ?

This project has been made for one big reason, getting rid of shader compilation stutters in game.
This was directly inspired by Dolphin's maintainers work on **ubershader**.

They already thought about a possible shader interpreter, but the cost of implementing it seemed to high for the rewards. Ubershader was like a simplified attempt (but nonetheless extremely complicated) at this.

Instead of a real interpretation, every shader was just combine into one titan shader that was compiled once and could run the game while the real shader were compiled in the background.

To make it possible it took an incredible amount of work and of course, is no solution you can recommend to anyone who doesn't know tf they are doing.
Ubershaders scale poorly, it worked for dolphin because the gamecube had a finite (and reasonable) amount of shaders and pipelines, but that might not always be the case.

They also incurs a huge pressure on GPU register, making them way slow to run (added to being slow to compile)

So **CVM** is just my attempt at making the idea of shader interpreter true.
Really being able to interpret shader on GPU without the gimmick that is the ubershader. 

Shaders are written in Nim, translated to bytecode and executed in the VM, as simple as that.

## Why Nim ?

Writing a VM from scratch is pure hell. So instead of trying to parse shader code I just try to use a preexisting language infrastructure.
However, I needed a langage that easily offer access to it's internal representation and allow to process whole modules (or functions).

Most languages don't allow you to do that in a stable way because they don't really offer any API contract over the compiler's internals.
So came Nim (Nimony/Nim3).

With his compiler plugins (which act as user defined compiler pass), it's way easier to directly generate bytecode from a correct representation.
No more need to check semantic correctness, only have to check whether an operation is allowed on GPU or not.

This way, I got the whole front-end part of the VM done, plus there are tons of transpiler project for Nim -> shaderLang. So it made thing even easier!
Being able to use Nim for everything without writing a single line of shader code!

## Why use this ?

- Execute shader without compilation time.
- Easy hot-reload (just reread the bytecode) making dev time faster
- Can handle your graphic program while the real shader compile in the background
- Has a constant pressure on register (since the VM is the only program)
- Thread divergence only happens if the original code would have diverged because each thread runs the same bytecode
- VM memory efficiently fits in GPU cache

## Cons

- Way slower than a native GPU program.
- Still ongoing (handling more GPU construct, run on more shader langs, etc etc)