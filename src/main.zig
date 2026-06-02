// /////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2026 RoXimn
// This software is released under the MIT License.
// /////////////////////////////////////////////////////////////////////////////
const std = @import("std");
const args = @import("args");
const wad = @import("doom.zig");
const rl = @import("raylib");

////////////////////////////////////////////////////////////////////////////////
const MapLine = struct {
    v1: rl.Vector2,
    v2: rl.Vector2,
    flags: u16,
};

////////////////////////////////////////////////////////////////////////////////
pub fn readMapLines(
    gpa: std.mem.Allocator,
    io: std.Io,
    lineList: *std.ArrayList(MapLine),
    lumps: []wad.FileLump,
    mapLumpIndex: usize,
    ifile: []const u8,
) !void {
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

    try lineList.ensureTotalCapacity(gpa, lineDefs.len);
    lineList.items.len = lineDefs.len;

    for (lineList.items, 0..) |*line, i| {
        const lineDef = lineDefs[i];
        const v1 = vertexes[@intCast(lineDef.vdx1)];
        const v2 = vertexes[@intCast(lineDef.vdx2)];
        line.* = .{
            .v1 = rl.Vector2{
                .x = @as(f32, @floatFromInt(v1.x)),
                .y = -@as(f32, @floatFromInt(v1.y)),
            },
            .v2 = rl.Vector2{
                .x = @as(f32, @floatFromInt(v2.x)),
                .y = -@as(f32, @floatFromInt(v2.y)),
            },
            .flags = @bitCast(lineDefs[i].flags),
        };
    }
}

////////////////////////////////////////////////////////////////////////////////
/// Creates an optimized default camera layout centering the map
/// while explicitly calculating aspect ratio fitting scales.
pub fn autoFitCamera(lines: []const MapLine) rl.Camera2D {
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
        minX = @min(minX, @min(l.v1.x, l.v2.x));
        maxX = @max(maxX, @max(l.v1.x, l.v2.x));

        // Invert Y-axis to original values
        minY = @min(minY, @min(-l.v1.y, -l.v2.y));
        maxY = @max(maxY, @max(-l.v1.y, -l.v2.y));
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
    lines: []const MapLine,
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
const Alignment = enum {
    left,
    center,
    right,
};

const UiText = struct {
    const Self = @This();

    uiWidth: f32,
    uiHeight: f32,
    font: rl.Font,
    fontSize: f32,
    padding: f32,
    charSpacing: f32,
    lineSpacing: f32,
    textColor: rl.Color,

    fn draw(
        self: Self,
        comptime txt: []const u8,
        params: anytype,
        lineNum: f32,
        alignment: Alignment,
    ) !void {
        var localBuffer: [256]u8 = undefined;
        const formattedText: [:0]u8 = try std.fmt.bufPrintSentinel(
            &localBuffer,
            txt,
            params,
            0,
        );
        const textSize = rl.measureTextEx(
            self.font,
            formattedText,
            self.fontSize,
            self.charSpacing,
        );
        const x: f32 = switch (alignment) {
            .left => 0.0,
            .center => (self.uiWidth - textSize.x) / 2.0,
            .right => self.uiWidth - textSize.x,
        };
        const y: f32 = lineNum * (textSize.y + self.lineSpacing);

        rl.drawTextEx(
            self.font,
            formattedText,
            rl.Vector2{
                .x = self.padding + x,
                .y = self.padding + y,
            },
            self.fontSize,
            self.charSpacing,
            self.textColor,
        );
    }
};

////////////////////////////////////////////////////////////////////////////////
pub fn drawUi(
    customFont: rl.Font,
    mapNum: usize,
    mapCount: usize,
    lineCount: usize,
) !void {
    const margin = 10.0;
    var text = UiText{
        .uiWidth = @as(f32, @floatFromInt(rl.getScreenWidth())) - margin * 2.0,
        .uiHeight = @as(f32, @floatFromInt(rl.getScreenHeight())) - margin * 2.0,
        .font = customFont,
        .fontSize = 20.0,
        .padding = margin,
        .charSpacing = 1.0,
        .lineSpacing = 5.0,
        .textColor = rl.Color.gold,
    };

    try text.draw(
        "ZgDoom",
        .{},
        0.0,
        Alignment.center,
    );

    try text.draw(
        "MAP: {d:02} / {d:02}",
        .{ mapNum, mapCount },
        0.0,
        Alignment.left,
    );

    try text.draw(
        "Lines: {d}",
        .{lineCount},
        0.0,
        Alignment.right,
    );
}

////////////////////////////////////////////////////////////////////////////////
pub fn main(init: std.process.Init) !void {
    // Memory Allocator --------------------------------------------------------
    const gpa = init.gpa;
    const io = init.io;

    // Args Parser -------------------------------------------------------------
    var parser = try args.ArgumentParser.init(
        init.arena.allocator(),
        .{
            .name = "zgdoom",
            .config = args.Config.production(),
        },
    );
    defer parser.deinit();
    try parser.addPositional("input", .{
        .help = "Input WAD file to process",
    });

    try parser.addUintOption("level", .{
        .short = 'l',
        .help = "Starting map index (1 indexed). Default: 1",
    });

    try parser.addFlag("fullscreen", .{
        .short = 'f',
        .help = "Show full screen. Default: disabled",
    });
    try parser.addFlag("maximized", .{
        .short = 'x',
        .help = "Show maximized window. Default: disabled",
    });
    try parser.addUintOption("monitor", .{
        .short = 'm',
        .help = "Show on specific monitor (1 indexed). Default: 1",
    });

    try parser.addFlag("verbose", .{
        .short = 'v',
        .help = "Enable verbose output. Default: disabled",
    });

    var result = try parser.parseProcess(init);
    defer result.deinit();

    const wadFilename = result.getString("input").?;
    const verbose = result.getOrBool("verbose", false);
    const isFullscreen = result.getOrBool("fullscreen", false);
    const isMaximized = result.getOrBool("maximized", false);
    var level = result.getOrUint("level", 1);
    var monitor: i32 = @as(i32, @intCast(result.getOrUint("monitor", 1)));

    // Dump --------------------------------------------------------------------
    _ = verbose; // for dump
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

    // Load Lines --------------------------------------------------------------
    var mapLines = try std.ArrayList(MapLine).initCapacity(
        gpa,
        1000,
    );
    defer mapLines.deinit(gpa);
    // Ensure user selected map index is in valid range [1 to LevelCount].
    level = @max(1, @min(level, mapIndices.len));
    // Convert to 0-indexed usize
    var mapIndex: usize = @as(usize, @intCast(level)) - 1;

    // Load lines data
    try readMapLines(
        gpa,
        io,
        &mapLines,
        lumps,
        mapIndices[mapIndex],
        wadFilename,
    );

    //--------------------------------------------------------------------------
    // GUI Initialization
    if (isFullscreen) {
        rl.setConfigFlags(.{ .fullscreen_mode = true });
    } else {
        rl.setConfigFlags(.{ .window_resizable = true });
    }
    rl.initWindow(
        800,
        480,
        "ZgDoom",
    );
    defer rl.closeWindow();
    // Ensure user selected map index is in valid range [1 to LevelCount].
    const monitorCount: i32 = rl.getMonitorCount();
    monitor = if (monitorCount < 1) 0 else @max(1, @min(monitor, monitorCount));
    // Convert to 0-indexed usize
    rl.setWindowMonitor(monitor - 1);

    if (!isFullscreen and isMaximized) {
        rl.maximizeWindow();
    }
    rl.setTargetFPS(10);

    const customFont = try rl.loadFont("resources/Orbitron-SemiBold.ttf");
    defer rl.unloadFont(customFont);

    var camera: rl.Camera2D = autoFitCamera(mapLines.items);

    //--------------------------------------------------------------------------
    // Main loop
    while (!rl.windowShouldClose()) {
        //----------------------------------------------------------------------
        // Update
        if (rl.isKeyPressed(rl.KeyboardKey.page_down)) {
            mapIndex = (mapIndex + 1) % mapIndices.len;
            try readMapLines(
                gpa,
                io,
                &mapLines,
                lumps,
                mapIndices[mapIndex],
                wadFilename,
            );
            camera = autoFitCamera(mapLines.items);
        }

        if (rl.isKeyPressed(rl.KeyboardKey.page_up)) {
            const newIndex = mapIndex -| 1;
            mapIndex = if (newIndex == mapIndex) mapIndices.len - 1 else newIndex;
            try readMapLines(
                gpa,
                io,
                &mapLines,
                lumps,
                mapIndices[mapIndex],
                wadFilename,
            );
            camera = autoFitCamera(mapLines.items);
        }

        //----------------------------------------------------------------------
        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        drawWadMap(mapLines.items, &camera);

        try drawUi(
            customFont,
            mapIndex + 1,
            mapIndices.len,
            mapLines.items.len,
        );
        //----------------------------------------------------------------------
    }
}

////////////////////////////////////////////////////////////////////////////////
