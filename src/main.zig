// /////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2026 RoXimn
// This software is released under the MIT License.
// /////////////////////////////////////////////////////////////////////////////
const std = @import("std");
const args = @import("args");
const wad = @import("doom.zig");
const rl = @import("raylib");

////////////////////////////////////////////////////////////////////////////////
/// Print formatted output to fixed sized buffer, truncating any overflows
fn fmtFixedBuffer(buffer: []u8, comptime fmt: []const u8, params: anytype) [:0]u8 {
    // 1. Reserve the last byte for our null-terminator sentinel
    const maxSafeLength = buffer.len - 1;
    const safeBuffer = buffer[0..maxSafeLength];
    const written = std.fmt.bufPrint(safeBuffer, fmt, params) catch |err| switch (err) {
        error.NoSpaceLeft => safeBuffer, // Truncation event; return the full safe slice
    };
    buffer[written.len] = 0;
    return buffer[0..written.len :0];
}

////////////////////////////////////////////////////////////////////////////////
pub fn drawFlagSegmentedCircle(
    center: rl.Vector2,
    radius: f32,
    flags: i16,
) void {
    inline for (0..3) |i| {
        const startAngle, const endAngle = switch (i) {
            0 => .{ 0.0, 144.0 },
            1 => .{ 144.0, 216.0 },
            2 => .{ 216.0, 360.0 },
            else => unreachable,
        };
        const drawColor = switch (i) {
            0 => if ((flags & 0x0001) != 0) rl.Color.maroon else rl.Color.light_gray,
            1 => if ((flags & 0x0002) != 0) rl.Color.orange else rl.Color.light_gray,
            2 => if ((flags & 0x0004) != 0) rl.Color.yellow else rl.Color.light_gray,
            else => unreachable,
        };
        rl.drawCircleSector(
            center,
            radius,
            startAngle,
            endAngle,
            24,
            drawColor,
        );
    }
}

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
pub fn readMapThings(
    gpa: std.mem.Allocator,
    io: std.Io,
    thingsList: *std.ArrayList(wad.Thing),
    lumps: []wad.FileLump,
    mapLumpIndex: usize,
    ifile: []const u8,
) !void {
    const things = try wad.readThings(
        gpa,
        io,
        &lumps[mapLumpIndex + 1],
        ifile,
    );
    defer gpa.free(things);

    try thingsList.ensureTotalCapacity(gpa, things.len);
    thingsList.items.len = things.len;

    for (thingsList.items, 0..) |*thing, i| {
        thing.* = things[i];
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

    var minX: f32 = std.math.inf(f32);
    var maxX: f32 = -std.math.inf(f32);
    var minY: f32 = std.math.inf(f32);
    var maxY: f32 = -std.math.inf(f32);

    for (lines) |l| {
        minX = @min(minX, @min(l.v1.x, l.v2.x));
        maxX = @max(maxX, @max(l.v1.x, l.v2.x));

        // Invert Y-axis to original values
        minY = @min(minY, @min(l.v1.y, l.v2.y));
        maxY = @max(maxY, @max(l.v1.y, l.v2.y));
    }

    const mapWidth = maxX - minX;
    const mapHeight = maxY - minY;

    const mapCenterX = minX + (mapWidth / 2.0);
    const mapCenterY = minY + (mapHeight / 2.0);

    const screenWidth = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screenHeight = @as(f32, @floatFromInt(rl.getScreenHeight()));

    // Aspect Ratio Corrections: Determine limits dynamically
    const zoomX = screenWidth / mapWidth;
    const zoomY = screenHeight / mapHeight;

    // Choose the smaller zoom value to fit the map completely without stretching
    const idealZoom = @min(zoomX, zoomY) * 0.9;

    return rl.Camera2D{
        // Anchor point to the middle of the display window
        .offset = .{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 },
        .target = .{ .x = mapCenterX, .y = mapCenterY },
        .rotation = 0.0,
        .zoom = idealZoom,
    };
}

////////////////////////////////////////////////////////////////////////////////
/// Renders the Doom 2D level map with fully managed camera transformations,
/// aspect-ratio preservation, and pan/zoom interactivity.
pub fn drawWadMap(
    lines: []const MapLine,
    things: []const wad.Thing,
    font: rl.Font,
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
        var lineColor = rl.Color.red;
        if ((line.flags & wad.ML_SECRET) != 0) {
            lineColor = rl.Color.yellow;
        } else if ((line.flags & wad.ML_TWOSIDED) != 0) {
            lineColor = rl.Color.brown;
        }
        rl.drawLineV(line.v1, line.v2, lineColor);
    }
    var buffer: [256]u8 = undefined;
    const fontSize = 10;
    const charSpacing = 0.0;
    for (things) |thing| {
        const center = rl.Vector2{
            .x = @as(f32, @floatFromInt(thing.x)),
            .y = -@as(f32, @floatFromInt(thing.y)),
        };
        const radius = 10.0;
        const angleDegrees = @as(f32, @floatFromInt(thing.angle));
        const angleRadians = angleDegrees * (std.math.pi / 180.0);

        // Calculate the end point of the radial line
        const targetX = center.x + (radius * @cos(angleRadians));
        // Subtract for Y to point 45° "up and right"as Raylib's Y-axis points downward.
        const targetY = center.y - (radius * @sin(angleRadians));
        const lineEnd = rl.Vector2{ .x = targetX, .y = targetY };

        drawFlagSegmentedCircle(
            center,
            radius,
            thing.flags,
        );
        rl.drawLineEx(center, lineEnd, 2.0, rl.Color.black);
        rl.drawCircleV(
            center,
            3.0,
            if (thing.flags & 0x0010 != 0) rl.Color.dark_green else rl.Color.black,
        );

        var label: [:0]u8 = undefined;
        if (std.enums.fromInt(wad.ThingType, thing.id)) |thingType| {
            label = fmtFixedBuffer(&buffer, "{s}", .{thingType.toString()});
        } else {
            label = fmtFixedBuffer(&buffer, "?[{d}]", .{thing.id});
        }

        const textSize = rl.measureTextEx(
            font,
            label,
            fontSize,
            charSpacing,
        );
        rl.drawTextEx(
            font,
            label,
            rl.Vector2{
                .x = center.x - (textSize.x / 2.0),
                .y = center.y + radius + 5,
            },
            fontSize,
            charSpacing,
            rl.Color.dark_gray,
        );
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
        lineNum: u32,
        alignment: Alignment,
    ) !void {
        var localBuffer: [256]u8 = undefined;
        const formattedText: [:0]u8 = fmtFixedBuffer(
            &localBuffer,
            txt,
            params,
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
        const y: f32 = @as(f32, @floatFromInt(lineNum)) * (textSize.y + self.lineSpacing);

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
    mapNum: usize,
    mapCount: usize,
    lineCount: usize,
    font: rl.Font,
    camera: *const rl.Camera2D,
) !void {
    const margin = 10.0;
    var text = UiText{
        .uiWidth = @as(f32, @floatFromInt(rl.getScreenWidth())) - margin * 2.0,
        .uiHeight = @as(f32, @floatFromInt(rl.getScreenHeight())) - margin * 2.0,
        .font = font,
        .fontSize = 32.0,
        .padding = margin,
        .charSpacing = 1.0,
        .lineSpacing = 3.0,
        .textColor = rl.Color.gold,
    };

    try text.draw(
        "ZgDoom",
        .{},
        0,
        Alignment.center,
    );

    try text.draw(
        "MAP: {d:02}/{d:02}",
        .{ mapNum, mapCount },
        0,
        Alignment.left,
    );

    try text.draw(
        "Lines: {d}",
        .{lineCount},
        0,
        Alignment.right,
    );
    try text.draw(
        "Zoom: {d:.1}%",
        .{camera.zoom},
        1,
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

    try parser.addFlag("dump", .{
        .short = 'd',
        .help = "Dump file contents to stdout and exit",
    });
    try parser.addFlag("verbose", .{
        .short = 'v',
        .help = "Enable verbose output. Default: disabled",
    });

    var result = try parser.parseProcess(init);
    defer result.deinit();

    const wadFilename = result.getString("input").?;
    const isFullscreen = result.getOrBool("fullscreen", false);
    const isMaximized = result.getOrBool("maximized", false);
    var level = result.getOrUint("level", 1);
    var monitor: i32 = @as(i32, @intCast(result.getOrUint("monitor", 1)));
    const isDump = result.getOrBool("dump", false);
    const isVerbose = result.getOrBool("verbose", false);

    if (isDump) {
        // Dump the file contents to stdout ------------------------------------
        try wad.dumpWad(
            gpa,
            std.Io.File.stdout(),
            io,
            wadFilename,
            isVerbose,
        );
    } else {
        // Start GUI -----------------------------------------------------------
        // Read Directory ------------------------------------------------------
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

        // Load Map Data -------------------------------------------------------
        // Ensure user selected map index is in valid range [1 to LevelCount].
        level = @max(1, @min(level, mapIndices.len));
        // Convert to 0-indexed usize
        var mapIndex: usize = @as(usize, @intCast(level)) - 1;

        // Load lines data
        var mapLines = try std.ArrayList(MapLine).initCapacity(gpa, 0);
        defer mapLines.deinit(gpa);
        try readMapLines(
            gpa,
            io,
            &mapLines,
            lumps,
            mapIndices[mapIndex],
            wadFilename,
        );

        // Load things data
        var mapThings = try std.ArrayList(wad.Thing).initCapacity(gpa, 0);
        defer mapThings.deinit(gpa);
        try readMapThings(
            gpa,
            io,
            &mapThings,
            lumps,
            mapIndices[mapIndex],
            wadFilename,
        );

        //----------------------------------------------------------------------
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

        const customFont = try rl.loadFont("resources/FiraCode-SemiBold.ttf");
        defer rl.unloadFont(customFont);

        var camera: rl.Camera2D = autoFitCamera(mapLines.items);

        //----------------------------------------------------------------------
        // Main loop
        while (!rl.windowShouldClose()) {
            //------------------------------------------------------------------
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
                try readMapThings(
                    gpa,
                    io,
                    &mapThings,
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
                try readMapThings(
                    gpa,
                    io,
                    &mapThings,
                    lumps,
                    mapIndices[mapIndex],
                    wadFilename,
                );
                camera = autoFitCamera(mapLines.items);
            }

            if (rl.isKeyPressed(rl.KeyboardKey.kp_)) {
                camera = autoFitCamera(mapLines.items);
            }

            if (rl.isKeyPressed(rl.KeyboardKey.kp_decimal)) {
                camera.zoom = if (camera.zoom == 1.0) 2.0 else if (camera.zoom == 2.0) 4.0 else 1.0;
            }

            //------------------------------------------------------------------
            // Draw
            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(rl.Color.black);

            drawWadMap(
                mapLines.items,
                mapThings.items,
                customFont,
                &camera,
            );

            try drawUi(
                mapIndex + 1,
                mapIndices.len,
                mapLines.items.len,
                customFont,
                &camera,
            );
            //------------------------------------------------------------------
        }
    }
}

////////////////////////////////////////////////////////////////////////////////
