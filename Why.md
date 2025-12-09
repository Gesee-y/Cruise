# Cruise: Why from Julia to Nim ?

For those who may not know, Julia is a High performance language mainly made for science.
Made to solve the 2 language problem (prototyping in one language, deploying in another one), it offers Matlab-like syntax, R-like vectorization, Lua-like syntax and C-like (or even more) performances. It's a JIT compiled and dynamically typed (but type can optionally be annotated for higher performances) language.

```julia
function foo(x)
  print(x) # code
end

foo(x)
```

While being an awesome language with powerful macros, dynamic dispatch, simple syntax, high performances, multithreading support and more, there where multiple reason that made me reconsider Julia as the host of my game engine.

At first, choosing Julia was more a hasty choice, I didn't want to make "yet another [insert maistream language] game engine", so I choosed an exotic language to work in peace without all the gatekeeping (given that I wasn't much of a great programmer at the time).
So I choose Julia and started making my own game engine.

Julia didn't cause any problem at the time, and everything was going smoothly, until I changed the core philosophy of the engine, from full game engine (which was a tremendous and time consuming) to a kernel.

This has revealed multiple flaws:

- Binary produced by Julia where still too big: compiling a simple kenel that does nothing to more than 1 Mb seemed to much
- JIT is not allowed on consoles: Which would have greatly reduced Cruise portability
- Multi paradigm: I wanted to allow programmer to use Cruise their way, Cruise didn't have support for some programming paradigm like OOP
- Game development ecosystem: Many game related library where not so updated

This lead me to consider another programming language to host my project, so I discovered Nim which seemed to be the perfect host:

- Support multiple dispatch (I can more or less transpose logics from Julia to Nim)
- Powerful macro system to reproduces the sugar syntax
- Easy to write while being high performances
- Multi paradigm
- More recent gamedev library