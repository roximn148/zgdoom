# 🛠️ DOOM WAD Viewer (Learning Zig)

This is a beginner's attempt at learning Zig language, in a desktop application built to read classic DOOM `.wad` files, extract game data, and render maps using a graphical interface. 

This repository serves as a personal playground to learn the **Zig programming language** and
explore low-level binary parsing, manual memory management, and data rendering
using the **Raylib** library.

---

## 🚀 Project Overview

The goal of this project is to parse the internal structures of a DOOM map file (WAD)
from scratch, map out the layout coordinates, and draw the results safely onto the screen [WAD].

### Current Progress & Key Learning Pillars
- [x] **Custom Error Handling**: Managing custom file parsing failures using Zig's explicit error sets (`!`).
- [x] **Manual Allocation**: Wrapping `std.heap.DebugAllocator` to track memory ownership and trace leaks cleanly.
- [x] **Data Manipulation**: Traversing arrays by pointer/reference (`|*item|`) to update dynamically generated game lump indices.
- [x] **Boundary Calculations**: COnverting and displaying different coordinate maps.
- [ ] **Raylib Integration**: Hooking up the engine loop to render parsed lines and vertices onto a 2D viewport [Raylib].

---

## 📁 Repository Structure

```text
├── src/
│   ├── main.zig          # Application entry point & memory allocation setup
│   └── doom.zig          # Byte parsing and dumping logic, Lump structs
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