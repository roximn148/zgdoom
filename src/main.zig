// /////////////////////////////////////////////////////////////////////////////
//  Copyright (c) 2026 RoXimn
// This software is released under the MIT License.
// /////////////////////////////////////////////////////////////////////////////
const std = @import("std");
const args = @import("args");
const wad = @import("doom.zig");
const rl = @import("raylib");

////////////////////////////////////////////////////////////////////////////////
const Line = struct {
    v1: rl.Vector2,
    v2: rl.Vector2,
    flags: u16,
};

////////////////////////////////////////////////////////////////////////////////
pub fn readMapLines(
    gpa: std.mem.Allocator,
    io: std.Io,
    lumps: []wad.FileLump,
    mapLumpIndex: usize,
    ifile: []const u8,
) ![]Line {
    const vertexes = try wad.readVertexes(
        gpa,
        io,
        &lumps[mapLumpIndex + 4],
        ifile,
    );
    defer gpa.free(vertexes);

    const lineDefs = try wad.readLineDefs(
        gpa,
        io,
        &lumps[mapLumpIndex + 2],
        ifile,
    );
    defer gpa.free(lineDefs);

    var lines = try gpa.alloc(Line, lineDefs.len);
    for (0..lines.len) |i| {
        const lineDef = lineDefs[i];
        const v1 = vertexes[@intCast(lineDef.vdx1)];
        const v2 = vertexes[@intCast(lineDef.vdx2)];
        lines[i].v1 = rl.Vector2{
            .x = @as(f32, @floatFromInt(v1.x)),
            .y = -@as(f32, @floatFromInt(v1.y)),
        };
        lines[i].v2 = rl.Vector2{
            .x = @as(f32, @floatFromInt(v2.x)),
            .y = -@as(f32, @floatFromInt(v2.y)),
        };
        lines[i].flags = @bitCast(lineDefs[i].flags);
    }
    return lines;
}

////////////////////////////////////////////////////////////////////////////////
inline fn smaller(f1: f32, f2: f32) f32 {
    return if (f1 < f2) f1 else f2;
}
inline fn larger(f1: f32, f2: f32) f32 {
    return if (f1 > f2) f1 else f2;
}

////////////////////////////////////////////////////////////////////////////////
/// Creates an optimized default camera layout centering the map
/// while explicitly calculating aspect ratio fitting scales.
pub fn initAutoFitCamera(lines: []const Line) rl.Camera2D {
    if (lines.len == 0) return rl.Camera2D{
        .offset = .{ .x = 0, .y = 0 },
        .target = .{ .x = 0, .y = 0 },
        .rotation = 0,
        .zoom = 1,
    };

    var minX: f32 = 32767.0;
    var maxX: f32 = -32768.0;
    var minY: f32 = 32767.0;
    var maxY: f32 = -32768.0;

    for (lines) |l| {
        minX = smaller(minX, smaller(l.v1.x, l.v2.x));
        maxX = larger(maxX, larger(l.v1.x, l.v2.x));

        // Invert Y-axis to original values
        minY = smaller(minY, larger(-l.v1.y, -l.v2.y));
        maxY = larger(maxY, larger(-l.v1.y, -l.v2.y));
    }

    const mapWidth = maxX - minX;
    const mapHeight = maxY - minY;

    const centerX = minX + (mapWidth / 2.0);
    const centerY = minY + (mapHeight / 2.0);

    const screenWidth = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screenHeight = @as(f32, @floatFromInt(rl.getScreenHeight()));

    // Aspect Ratio Corrections: Determine limits dynamically
    const zoomX = screenWidth / mapWidth;
    const zoomY = screenHeight / mapHeight;

    // Choose the smaller zoom value to fit the map completely without stretching
    const idealZoom = if (zoomX < zoomY) zoomX * 0.9 else zoomY * 0.9;

    return rl.Camera2D{
        // Anchor point to the middle of the display window
        .offset = .{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 },
        // Track the map center while explicitly flattening the inverted Y
        .target = .{ .x = centerX, .y = -centerY },
        .rotation = 0.0,
        .zoom = idealZoom,
    };
}

////////////////////////////////////////////////////////////////////////////////
/// Renders the Doom 2D level map with fully managed camera transformations,
/// aspect-ratio preservation, and pan/zoom interactivity.
pub fn drawWadMap(
    lines: []const Line,
    camera: *rl.Camera2D,
) void {
    // Interactivity: Process Zooming relative to the mouse pointer
    const wheel = rl.getMouseWheelMove();
    if (wheel != 0.0) {
        // Find exactly where the mouse pointer points inside Doom's coordinate bounds
        const mouseWorldPosition = rl.getScreenToWorld2D(rl.getMousePosition(), camera.*);

        // Pin the camera's screen-space offset anchor tightly to the cursor's location
        camera.offset = rl.getMousePosition();
        camera.target = mouseWorldPosition;

        // Apply scale factor modifications safely
        const zoomFactor: f32 = 1.15;
        if (wheel > 0.0) {
            camera.zoom *= zoomFactor;
        } else {
            camera.zoom /= zoomFactor;
        }

        // Clamp scaling thresholds to avoid zero divisions or heavy texture pixelation
        if (camera.zoom < 0.001) camera.zoom = 0.001;
        if (camera.zoom > 10.0) camera.zoom = 10.0;
    }

    // Interactivity: Process Drag Panning with Mouse Button
    if (rl.isMouseButtonDown(.right)) {
        var delta = rl.getMouseDelta();
        // Scale movement vector dynamically by inverse zoom value
        delta.x = delta.x / camera.zoom;
        delta.y = delta.y / camera.zoom;

        // Pan the target opposite to drag vector
        camera.target.x -= delta.x;
        // Compensating for Doom's inverted math logic: Y-dragging adds directly
        camera.target.y -= delta.y;
    }

    // 4. Begin Graphics Pipeline Drawing Phase
    rl.beginMode2D(camera.*);

    for (lines) |line| {

        // Differentiate line classifications visually using WAD Flags
        // For example: Secret sectors vs structural wall parameters
        var lineColor = rl.Color.red;
        if ((line.flags & 0x0020) != 0) { // Standard Doom secret flag bitmask
            lineColor = rl.Color.yellow;
        }

        // Draw crisp lines leveraging modern sub-pixel vector rendering vectors
        rl.drawLineV(line.v1, line.v2, lineColor);
    }

    rl.endMode2D();
}

////////////////////////////////////////////////////////////////////////////////
pub fn main(init: std.process.Init) !void {
    // Memory Allocator --------------------------------------------------------
    const gpa = init.gpa;
    const io = init.io;

    var parser = try args.ArgumentParser.init(
        init.arena.allocator(),
        .{ .name = "zdoom" },
    );
    defer parser.deinit();
    try parser.addPositional("input", .{
        .help = "Input WAD file to process",
    });

    try parser.addFlag("verbose", .{ .short = 'v' });
    try parser.addIntOption("level", .{
        .short = 'l',
        .help = "Map Index",
    });

    var result = try parser.parseProcess(init);
    defer result.deinit();

    const wadFilename = result.getString("input").?;
    const verbose = result.getBool("verbose") orelse false;
    const level = result.getInt("level") orelse 0;
    _ = verbose;
    // _ = level;

    // Dump --------------------------------------------------------------------
    // try wad.dumpWad(
    //     gpa,
    //     std.Io.File.stdout(),
    //     io,
    //     wadFilename,
    //     verbose,
    // );

    // Read Directory ----------------------------------------------------------
    const wadData = try wad.readWadDirectory(gpa, io, wadFilename);
    defer gpa.free(wadData);

    var wadDir: *wad.WadDirectory = @ptrCast(wadData.ptr);
    const lumps: []wad.FileLump = @as(
        [*]wad.FileLump,
        @ptrCast(&wadDir.lumps),
    )[0..wadDir.header.lumpCount];

    const mapIndices = try wad.getMapIndexes(gpa, lumps);
    defer gpa.free(mapIndices);
    if (mapIndices.len == 0) {
        return;
    }

    // File Reader -------------------------------------------------------------
    const mapIndex: usize = if (0 <= level and level < mapIndices.len) @intCast(level) else 0;
    const lines = try readMapLines(
        gpa,
        io,
        lumps,
        mapIndices[mapIndex],
        wadFilename,
    );
    defer gpa.free(lines);

    //--------------------------------------------------------------------------
    // GUI Initialization
    rl.setConfigFlags(.{ .fullscreen_mode = true });
    rl.initWindow(0, 0, "ZDoom");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    var camera: rl.Camera2D = initAutoFitCamera(lines);

    //--------------------------------------------------------------------------
    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update

        //----------------------------------------------------------------------
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        // Triggers user pan tracking, zoom math adjustments, and maps lines
        drawWadMap(lines, &camera);
        //----------------------------------------------------------------------
    }
}

////////////////////////////////////////////////////////////////////////////////
