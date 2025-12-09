# Cruise: Why Move from Julia to Nim?

For those who may not know, Julia is a high-performance language mainly designed for scientific computing.
Created to solve the "two-language problem" (prototyping in one language and deploying in another), it offers MATLAB-like syntax, R-like vectorization, Lua-like simplicity, and C-like (or even better) performance. It is JIT-compiled and dynamically typed, though types can optionally be annotated for higher performance.

```julia
function foo(x)
  print(x) # code
end

foo(x)
```

While Julia is an awesome language with powerful macros, dynamic dispatch, simple syntax, high performance, multithreading support, and more, there were several reasons that made me reconsider using it as the host for my game engine.

At first, choosing Julia was more of a hasty decision. I didn’t want to make “yet another [insert mainstream language] game engine,” so I picked an exotic language to work in peace, away from the gatekeeping (especially since I wasn’t a very experienced programmer at the time).
So I chose Julia and started building my own game engine.

Julia didn’t cause any problems at first, and everything went smoothly..., until I changed the core philosophy of the engine, from a full game engine (which was massive and time-consuming) to a kernel.

This revealed several flaws:

* **Binary size:** The binaries produced by Julia were still too large. Compiling a simple kernel that does almost nothing produced a binary over 1 MB, which seemed excessive.
* **JIT limitations:** JIT compilation isn’t allowed on consoles, which would have greatly reduced Cruise’s portability.
* **Multi-paradigm support:** I wanted to let programmers use Cruise in their own style, but Julia didn’t fully support some programming paradigms, like OOP.
* **Game development ecosystem:** Many game-related libraries were outdated or poorly maintained.

This led me to consider another programming language to host my project. That’s when I discovered Nim, which seemed like the perfect fit:

* Supports multiple dispatch (allowing me to transpose much of Julia’s logic into Nim)
* Powerful macro system for reproducing syntactic sugar
* Easy to write while still delivering high performance
* Multi-paradigm support
* More recent game development libraries and a more active community
* Cross-compilation
* Cross-platform

It felt like the holy grail: a quiet ecosystem where I could peacefully build my kernel without being lectured about the 10 other existing engines.
Here we are, I actually enjoy writing Nim code and find it to be an awesome language, much like Julia.
