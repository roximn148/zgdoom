# 🛠️ DOOM WAD Viewer (Learning Zig)

This is a beginner's attempt at learning Zig language, in a desktop application built to read classic DOOM `.wad` files, extract game data, and render maps using a graphical interface. 

This repository serves as a personal playground to learn the **Zig programming language** and
explore low-level binary parsing, manual memory management, and data rendering
using the **Raylib** library.

---

## 🚀 Project Overview

The goal of this project is to parse the internal structures of a DOOM map file (WAD)
from scratch, map out the layout coordinates, and draw the results safely onto the screen [WAD].

### Current Progress & Key Takeaways
- **Error Handling**:
    - [x] Managing errors using try, catch, and switch blocks.
    - [x] Creating and raising custom error.
    - [x] Handling errors with catch block, with/without returning values.
    - [ ] Implementing error sets.
- **Heap Allocation**:
    - [x] Tracking memory allocation lifespans, leaks and ownership using `std.heap.DebugAllocator`.
    - [x] Casting generic allocated buffers into structs and slices.
    - [x] Returning allocated arrays and structs from functions to callers.
    - [x] Passing dynamic arrays into functions for reading and editing.
- **Data Manipulation**:
    - [x] Defining, allocating and modifying `struct`s.
    - [x] Reading structs from `File` streams.
    - [x] Writing formatted output to `File` streams, including stdout.
    - [x] Custom formatting of structs
    - [x] Struct functions with dynamically allocated fields.
    - [x] `init` and `deinit` struct functions with allocator usage.
    - [x] Use of `enum` for labeling numeral values, both for programmer and user.
- **Optional**
    - [x] Creating and null initialized optional variables.
    - [x] Handling null situation, with `.?`, `orelse` and `if`.
- **Dependency Management**
    - [x] Adding and linking external dependency modules.
- **Command Line Arguments**
    - [x] Adding and managing command-line arguments.
- **Raylib**:
    - [x] Conversion from DOOM world coordinate system to screen coordinate system.
    - [x] Map rendering in 2D using the Raylib engine.
    - [x] Basic UI overlay, keyboard and mouse interactive navigation.
    - [x] Dynamic zoom adjustment; AutoFit and ActualSize.
    - [x] Parameterized formatted UI text rending with custom font family/size, alignment, spacing and color.
    - [x] Circle, Sector drawing
    - [x] Screen <-> World coordinate mapping and transformation
    - [x] Dynamic sprite/texture loading and drawing
    - [x] Customizing cursor
- **DVUI**:
    - [x] Basic application build and initialization.
    - [x] Use raylib-zig backend and integration with raylib-zig drawing.

## 📁 Repository Structure

```text
├── src/
│   ├── main.zig          # Application entry point & memory allocation setup
│   └── doom.zig          # Byte parsing and dumping logic, Lump structs
│   └── utils.zig         # Miscellaneous supporting functions
├── build.zig             # Zig native compilation instructions
├── build.zig.zon         # Package manager settings (Raylib dependencies)
├── .gitignore            # Clean environment configurations for Zig and VS Code
└── README.md             # You are here!
```

---

## 🛠️ Prerequisites

* **Zig Compiler**: Version `0.16.0` or newer.

---

## 📜 Acknowledgments & Resources

- [Zig Language](https://ziglang.org) — Zig is a general-purpose programming language and toolchain for maintaining robust, optimal and reusable software.
- [The Unofficial Doom Specs](https://doomwiki.org) — The unofficial doceumentiona of how WAD headers, lumps, and directories are stored in binary format.
- [Raylib Zig Bindings]() — Manually tweaked, auto-generated [Raylib](https://raylib.com). bindings for zig.
- [Args.zig](https://github.com/muhammad-fiaz/args.zig) — A fast, powerful, and developer-friendly command-line argument parsing library for Zig.