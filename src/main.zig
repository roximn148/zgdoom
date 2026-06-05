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
pub fn getPlayer1Start(thingsList: []wad.Thing) rl.Vector2 {
    var startPosition = rl.Vector2{ .x = 0.0, .y = 0.0 };
    for (thingsList) |thing| {
        if (std.enums.fromInt(wad.ThingType, thing.id)) |thingType| {
            if (thingType == .Player1Start) {
                startPosition.x = @as(f32, @floatFromInt(thing.x));
                startPosition.y = -@as(f32, @floatFromInt(thing.y));
                break;
            }
        }
    }
    return startPosition;
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

    // Aspect Ratio selection for zoom factor
    const optimalZoom = @min(screenWidth / mapWidth, screenHeight / mapHeight) * 0.9;

    return rl.Camera2D{
        // Anchor to the middle of the display window
        .offset = .{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 },
        // Target the map center in World coordinates
        .target = .{ .x = mapCenterX, .y = mapCenterY },
        .rotation = 0.0,
        .zoom = optimalZoom,
    };
}

////////////////////////////////////////////////////////////////////////////////
/// Renders the Doom 2D level map with fully managed camera transformations,
/// aspect-ratio preservation, and pan/zoom interactivity.
pub fn drawWadMap(
    lines: []const MapLine,
    things: []const wad.Thing,
    font: rl.Font,
    camera: rl.Camera2D,
) void {
    rl.beginMode2D(camera);

    // -------------------------------------------------------------------------
    for (lines) |line| {
        var lineColor = rl.Color.red;
        if ((line.flags & wad.ML_SECRET) != 0) {
            lineColor = rl.Color.yellow;
        } else if ((line.flags & wad.ML_TWOSIDED) != 0) {
            lineColor = rl.Color.brown;
        }
        rl.drawLineV(line.v1, line.v2, lineColor);
    }

    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
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
    ) void {
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
    camera: rl.Camera2D,
) void {
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

    text.draw("ZgDoom", .{}, 0, Alignment.center);

    text.draw("MAP: {d:02}/{d:02}", .{ mapNum, mapCount }, 0, Alignment.left);

    text.draw("Lines: {d}", .{lineCount}, 0, Alignment.right);
    text.draw("Zoom: {d:.2}%", .{camera.zoom}, 1, Alignment.right);
}

////////////////////////////////////////////////////////////////////////////////
/// A visual 31x31 blueprint string representing the crosshair sprite layout.
/// '.' indicates a transparent background pixel.
/// '#' indicates a solid white crosshair line pixel.
/// '+' indicates a distinct center core color (red dot).
/// '@' indicates highlight color (green)
const diamondCircleBlueprint =
    \\...............................
    \\...............@...............
    \\.............##@##.............
    \\...........##..@..##...........
    \\.........##....@....##.........
    \\.......##......@......##.......
    \\......#........@........#......
    \\.....#...................#.....
    \\....#.....................#....
    \\...#.......................#...
    \\...#...........#...........#...
    \\..#...........#.#...........#..
    \\..#..........#...#..........#..
    \\.#..........#.....#..........#.
    \\.#.........#.......#.........#.
    \\@@@@@@@...#....+....#...@@@@@@@
    \\.#.........#.......#.........#.
    \\.#..........#.....#..........#.
    \\..#..........#...#..........#..
    \\..#...........#.#...........#..
    \\...#...........#...........#...
    \\...#.......................#...
    \\....#.....................#....
    \\.....#...................#.....
    \\......#........@........#......
    \\.......##......@......##.......
    \\.........##....@....##.........
    \\...........##..@..##...........
    \\.............##@##.............
    \\...............@...............
    \\...............................
;
const chevronCornersBlueprint =
    \\...............................
    \\..#######.............#######..
    \\..#....#...............#....#..
    \\..#...#.................#...#..
    \\..#..#...................#..#..
    \\..#.#.....................#.#..
    \\..##.......................##..
    \\..#.........................#..
    \\...............................
    \\.........#............#........
    \\...............................
    \\...........#........#..........
    \\...............................
    \\...............................
    \\...............................
    \\...............+...............
    \\...............................
    \\...............................
    \\...............................
    \\...........#.......#...........
    \\...............................
    \\.........#...........#.........
    \\...............................
    \\..#.........................#..
    \\..##.......................##..
    \\..#.#.....................#.#..
    \\..#..#...................#..#..
    \\..#...#.................#...#..
    \\..#....#...............#....#..
    \\..#######.............#######..
    \\...............................
;
const dotMatrixBlueprint =
    \\...............................
    \\...............#...............
    \\...............................
    \\...............................
    \\...............................
    \\...............#...............
    \\...............................
    \\.......@@@@@.......@@@@@.......
    \\.......@...............@.......
    \\.......@.......#.......@.......
    \\.......@...............@.......
    \\.......@...............@.......
    \\...............................
    \\...............................
    \\...............................
    \\.#...#...#.....+.....#...#...#.
    \\...............................
    \\...............................
    \\...............................
    \\.......@...............@.......
    \\.......@...............@.......
    \\.......@.......#.......@.......
    \\.......@...............@.......
    \\.......@@@@@.......@@@@@.......
    \\...............................
    \\...............#...............
    \\...............................
    \\...............................
    \\...............................
    \\...............#...............
    \\...............................
;
const starBlueprint =
    \\...............................
    \\...............................
    \\...............#...............
    \\...............#...............
    \\...............#...............
    \\...............#...............
    \\...............#...............
    \\.......@.......#.......@.......
    \\.......@.......#.......@.......
    \\.......@.......#.......@.......
    \\........@......#......@........
    \\.........@.....#.....@.........
    \\..........@....#....@..........
    \\...........@.......@...........
    \\............@.....@............
    \\.#######....@..+..@....#######.
    \\............@.....@............
    \\...........@.......@...........
    \\..........@....#....@..........
    \\.........@.....#.....@.........
    \\........@......#......@........
    \\.......@.......#.......@.......
    \\.......@.......#.......@.......
    \\.......@.......#.......@.......
    \\...............#...............
    \\...............#...............
    \\...............#...............
    \\...............#...............
    \\...............#...............
    \\...............................
    \\...............................
;
const plusBlueprint =
    \\...............................
    \\...............................
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\...............@...............
    \\...............@...............
    \\...............................
    \\...............................
    \\.#########...........#########.
    \\.@@@@@@@@@@@...+...@@@@@@@@@@@.
    \\.#########...........#########.
    \\...............................
    \\...............................
    \\...............@...............
    \\...............@...............
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\..............#@#..............
    \\...............................
    \\...............................
;
const fancySciFiHudBlueprint =
    \\..@@@...................###....
    \\..@..@@...............##..#....
    \\..@....@.............#....#....
    \\...@....@................#.....
    \\....@....@.#######......#......
    \\.........##.......##...#.......
    \\.......##...#...#...##.........
    \\......#....#.....#....#........
    \\.....#....#.......#....#.......
    \\....#....#.........#....#......
    \\...#....#...........#....#.....
    \\...#...#.............#...#.....
    \\..#...#...............#...#....
    \\..#..#.................#..#....
    \\..#..#.................#..#....
    \\..#..#........+........#..#....
    \\..#..#.................#..#....
    \\..#..#.................#..#....
    \\..#...#...............#...#....
    \\...#...#@@@@@@@@@@@@@#...#.....
    \\...#....#...........#....#.....
    \\....#....#.........#....#......
    \\.....#....#.......#....#.......
    \\......#....#.....#....#........
    \\.......##...#...#...##@........
    \\.........##.......#....@.......
    \\....#....#.#######......@......
    \\...#....#................@.....
    \\..#....#.............@....@....
    \\..#..##...............@@..@....
    \\..###...................@@@....
;
const hazardCoreBlueprint =
    \\...............................
    \\............#######............
    \\..........##.......##..........
    \\........##...........##........
    \\.......#...............#.......
    \\.....##...###########...##.....
    \\....#...##...........##...#....
    \\...#...#...............#...#...
    \\...#..#........#........#..#...
    \\..#..#........###........#..#..
    \\..#..#.......##.##.......#..#..
    \\..#.#.......##...##.......#.#..
    \\..#.#......##.....##......#.#..
    \\.#..#.....##.......##.....#..#.
    \\.#..#....##.........##....#..#.
    \\.#..#....#.....+.....#....#..#.
    \\.#..#....##.........##....#..#.
    \\.#..#.....##.......##.....#..#.
    \\..#.#......##.....##......#.#..
    \\..#.#.......##...##.......#.#..
    \\..#..#.......##.##.......#..#..
    \\..#..#........###........#..#..
    \\...#..#........#........#..#...
    \\...#...#...............#...#...
    \\....#...##...........##...#....
    \\.....##...###########...##.....
    \\.......#...............#.......
    \\........##...........##........
    \\..........##.......##..........
    \\............#######............
    \\...............................
;
const deltaCoreBlueprint =
    \\...............................
    \\...............#...............
    \\..............#@#..............
    \\.............#.@.#.............
    \\............#..@..#............
    \\...........#...@...#...........
    \\..........#.........#..........
    \\.........#.....#.....#.........
    \\........#......#......#........
    \\.......#.......#.......#.......
    \\......#.................#......
    \\.....#.........#.........#.....
    \\....#..........#..........#....
    \\...#.......................#...
    \\..#.........................#..
    \\.#.......@.....+.....@.......#.
    \\.#...........................#.
    \\.#...........................#.
    \\..#............#............#..
    \\...#...........#...........#...
    \\....#.....................#....
    \\.....#.........@.........#.....
    \\......#........@........#......
    \\.......#.......@.......#.......
    \\........@@@@@@@@@@@@@@@........
    \\.........#...#...#...#.........
    \\..........#..#...#..#..........
    \\...........#.#...#.#...........
    \\............##...##............
    \\.............#...#.............
    \\...............................
;

const CursorStyle = enum {
    diamondCircle,
    chevronCorners,
    dotMatrix,
    star,
    plus,
    fancySciFiHud,
    hazardCore,
    deltaCore,

    const count = std.meta.fields(CursorStyle).len;

    pub fn cycle(self: CursorStyle, direction: i2) CursorStyle {
        const total = @as(i32, @intCast(count));
        var nextIndex = @as(i32, @intFromEnum(self)) + direction;
        if (nextIndex < 0) nextIndex = total - 1;
        if (nextIndex >= total) nextIndex = 0;
        return @enumFromInt(nextIndex);
    }
};

const blueprints: [CursorStyle.count][]const u8 = .{
    // The order of these should match the corresponding enum
    diamondCircleBlueprint,
    chevronCornersBlueprint,
    dotMatrixBlueprint,
    starBlueprint,
    plusBlueprint,
    fancySciFiHudBlueprint,
    hazardCoreBlueprint,
    deltaCoreBlueprint,
};

////////////////////////////////////////////////////////////////////////////////
/// Parses an enumerated 31 x 31 string blueprint and creates Texture2D as a sprite.
pub fn createCursorTexture(
    allocator: std.mem.Allocator,
    cursorStyle: CursorStyle,
) !rl.Texture2D {
    const width = 31;
    const height = 31;
    const pixelCount = width * height;

    // Allocate memory for RGBA pixels
    const pixels = try allocator.alloc(rl.Color, pixelCount);
    defer allocator.free(pixels);

    // Filter out newline characters and parse the string pattern linearly
    const styleIndex = @as(usize, @intCast(@intFromEnum(cursorStyle)));
    var pixelIndex: usize = 0;
    for (blueprints[styleIndex]) |char| {
        switch (char) {
            // Newline characters (\n or \r) are skipped over
            '\n', '\r' => continue,

            // Map ASCII characters directly to explicit color definitions
            '.' => {
                pixels[pixelIndex] = rl.Color.blank; // Transparent
                pixelIndex += 1;
            },
            '#' => {
                pixels[pixelIndex] = rl.Color.white; // Custom Crosshair Stroke
                pixelIndex += 1;
            },
            '+' => {
                pixels[pixelIndex] = rl.Color.red; // Core target center point
                pixelIndex += 1;
            },
            '@' => {
                pixels[pixelIndex] = rl.Color.green; // Highlights
                pixelIndex += 1;
            },
            else => {
                // Ignore remaining characters
                continue;
            },
        }
    }

    // Safety verification check ensuring the array maps exactly onto allocated canvas space
    std.debug.assert(pixelIndex == pixelCount);

    // Build the metadata header object wrapper around our heap memory layout pointer
    const img = rl.Image{
        .data = pixels.ptr,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = .uncompressed_r8g8b8a8,
    };

    // Upload the raw color bytes directly to the GPU structure memory space
    return rl.loadTextureFromImage(img);
}

////////////////////////////////////////////////////////////////////////////////
/// Draws a 3px thick crosshair with an empty center gap
pub fn drawCrosshair(
    crosshairSprite: rl.Texture,
    center: rl.Vector2,
    label: [:0]const u8,
    fontSize: i32,
    textColor: rl.Color,
) void {
    // Central dot -------------------------------------------------------------
    const positionX = @as(i32, @intFromFloat(@ceil(center.x)));
    const positionY = @as(i32, @intFromFloat(@floor(center.y)));
    rl.drawTexture(crosshairSprite, positionX - 15, positionY - 15, rl.Color.white);

    // Lower-Right Quadrant Text Alignment -------------------------------------
    // Define padding relative to the center dot
    const paddingX = -@divTrunc(rl.measureText(label, fontSize), 2);
    const paddingY = 15 + fontSize;

    rl.drawText(
        label,
        positionX + paddingX,
        positionY + paddingY,
        fontSize,
        textColor,
    );
}

////////////////////////////////////////////////////////////////////////////////
pub fn drawWorldGrid(
    camera: rl.Camera2D,
    minorColor: rl.Color,
    majorColor: rl.Color,
    axisColor: rl.Color,
) void {
    const minScreenInterval: f32 = 50.0;
    const rawStep = minScreenInterval / camera.zoom;
    const power = @ceil(std.math.log2(rawStep / minScreenInterval));
    const factor = std.math.pow(f32, 2.0, power);
    const fMinorStep = minScreenInterval * factor;
    const fMajorStep = fMinorStep * 5.0; // Major lines/dots interval

    const screenWidth = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const screenHeight = @as(f32, @floatFromInt(rl.getScreenHeight()));

    const topLeft = rl.getScreenToWorld2D(rl.Vector2{ .x = 0.0, .y = 0.0 }, camera);
    const bottomRight = rl.getScreenToWorld2D(rl.Vector2{ .x = screenWidth, .y = screenHeight }, camera);

    // 2. Compute loop boundaries snapped to the minor step size
    const startX = @as(i32, @intFromFloat(@floor(topLeft.x / fMinorStep) * fMinorStep));
    const endX = @as(i32, @intFromFloat(@ceil(bottomRight.x / fMinorStep) * fMinorStep));
    const startY = @as(i32, @intFromFloat(@floor(topLeft.y / fMinorStep) * fMinorStep));
    const endY = @as(i32, @intFromFloat(@ceil(bottomRight.y / fMinorStep) * fMinorStep));

    const minorStep = @as(i32, @intFromFloat(fMinorStep));
    const majorStep = @as(i32, @intFromFloat(fMajorStep));

    var x = startX;
    while (x <= endX) : (x += minorStep) {
        if (x == 0) continue;

        const isXMajor = @mod(x, majorStep) == 0;
        const x_f = @as(f32, @floatFromInt(x));

        var y = startY;
        while (y <= endY) : (y += minorStep) {
            if (y == 0) continue;

            const isYMajor = @mod(y, majorStep) == 0;
            const color = if (isXMajor and isYMajor) majorColor else minorColor;

            rl.drawPixelV(
                rl.getWorldToScreen2D(
                    rl.Vector2{ .x = x_f, .y = @as(f32, @floatFromInt(y)) },
                    camera,
                ),
                color,
            );
        }
    }

    // X Axis (Horizontal Line along Y = 0)
    if (topLeft.y <= 0.0 and bottomRight.y >= 0.0) {
        rl.drawLineV(
            rl.getWorldToScreen2D(rl.Vector2{ .x = topLeft.x, .y = 0.0 }, camera),
            rl.getWorldToScreen2D(rl.Vector2{ .x = bottomRight.x, .y = 0.0 }, camera),
            axisColor,
        );
    }

    // Y Axis (Vertical Line along X = 0)
    if (topLeft.x <= 0.0 and bottomRight.x >= 0.0) {
        rl.drawLineV(
            rl.getWorldToScreen2D(rl.Vector2{ .x = 0.0, .y = topLeft.y }, camera),
            rl.getWorldToScreen2D(rl.Vector2{ .x = 0.0, .y = bottomRight.y }, camera),
            axisColor,
        );
    }
}

////////////////////////////////////////////////////////////////////////////////
pub fn main(init: std.process.Init) !void {
    // Memory Allocator --------------------------------------------------------
    const allocator = init.gpa;
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
            allocator,
            std.Io.File.stdout(),
            io,
            wadFilename,
            isVerbose,
        );
    } else {
        // Start GUI -----------------------------------------------------------
        // Read Directory ------------------------------------------------------
        const wadData = try wad.readWadDirectory(allocator, io, wadFilename);
        defer allocator.free(wadData);

        var wadDir: *wad.WadDirectory = @ptrCast(wadData.ptr);
        const lumps: []wad.FileLump = @as(
            [*]wad.FileLump,
            @ptrCast(&wadDir.lumps),
        )[0..wadDir.header.lumpCount];

        const mapIndices = try wad.getMapIndexes(allocator, lumps);
        defer allocator.free(mapIndices);
        if (mapIndices.len == 0) {
            return;
        }

        // Load Map Data -------------------------------------------------------
        // Ensure user selected map index is in valid range [1 to LevelCount].
        level = @max(1, @min(level, mapIndices.len));
        // Convert to 0-indexed usize
        var mapIndex: usize = @as(usize, @intCast(level)) - 1;

        // Load lines data
        var mapLines = try std.ArrayList(MapLine).initCapacity(allocator, 0);
        defer mapLines.deinit(allocator);
        try readMapLines(
            allocator,
            io,
            &mapLines,
            lumps,
            mapIndices[mapIndex],
            wadFilename,
        );

        // Load things data
        var mapThings = try std.ArrayList(wad.Thing).initCapacity(allocator, 0);
        defer mapThings.deinit(allocator);
        try readMapThings(
            allocator,
            io,
            &mapThings,
            lumps,
            mapIndices[mapIndex],
            wadFilename,
        );
        var playerStart = getPlayer1Start(mapThings.items);

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

        var activeStyle = CursorStyle.dotMatrix;
        var crosshairTexture = try createCursorTexture(
            allocator,
            activeStyle,
        );
        defer rl.unloadTexture(crosshairTexture);
        rl.hideCursor();

        const customFont = try rl.loadFont("resources/FiraCode-SemiBold.ttf");
        defer rl.unloadFont(customFont);

        var camera: rl.Camera2D = autoFitCamera(mapLines.items);

        //----------------------------------------------------------------------
        // UI constants
        const zoomMin: f32 = 0.05;
        const zoomMax: f32 = 10.0;
        const zoomStepMinor: f32 = 0.05;
        const zoomStepMajor: f32 = 0.50;
        const moveStepMinor: f32 = 10.0;
        const moveStepMajor: f32 = 100.0;

        //----------------------------------------------------------------------
        // Main loop
        while (!rl.windowShouldClose()) {
            //------------------------------------------------------------------
            // Update
            const isShiftDown = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);

            if (rl.isKeyPressed(.page_down)) {
                mapIndex = (mapIndex + 1) % mapIndices.len;
                try readMapLines(
                    allocator,
                    io,
                    &mapLines,
                    lumps,
                    mapIndices[mapIndex],
                    wadFilename,
                );
                try readMapThings(
                    allocator,
                    io,
                    &mapThings,
                    lumps,
                    mapIndices[mapIndex],
                    wadFilename,
                );
                playerStart = getPlayer1Start(mapThings.items);
                camera = autoFitCamera(mapLines.items);
            }

            if (rl.isKeyPressed(.page_up)) {
                const newIndex = mapIndex -| 1;
                mapIndex = if (newIndex == mapIndex) mapIndices.len - 1 else newIndex;
                try readMapLines(
                    allocator,
                    io,
                    &mapLines,
                    lumps,
                    mapIndices[mapIndex],
                    wadFilename,
                );
                try readMapThings(
                    allocator,
                    io,
                    &mapThings,
                    lumps,
                    mapIndices[mapIndex],
                    wadFilename,
                );
                playerStart = getPlayer1Start(mapThings.items);
                camera = autoFitCamera(mapLines.items);
            }

            if (rl.isKeyPressed(.kp_divide)) {
                camera.target = playerStart;
                camera.offset = rl.Vector2{
                    .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
                    .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
                };
            }

            if (rl.isKeyPressed(.kp_multiply)) {
                camera = autoFitCamera(mapLines.items);
            }

            if (rl.isKeyPressed(.kp_decimal)) {
                camera.zoom = if (camera.zoom == 1.0) 2.0 else if (camera.zoom == 2.0) 4.0 else 1.0;
            }

            if (rl.isKeyDown(.kp_add)) {
                if (isShiftDown) {
                    camera.zoom = @max(zoomMin, @min(camera.zoom + zoomStepMajor, zoomMax));
                } else {
                    camera.zoom = @max(zoomMin, @min(camera.zoom + zoomStepMinor, zoomMax));
                }
            }

            if (rl.isKeyDown(.kp_subtract)) {
                if (isShiftDown) {
                    camera.zoom = @max(zoomMin, @min(camera.zoom - zoomStepMajor, zoomMax));
                } else {
                    camera.zoom = @max(zoomMin, @min(camera.zoom - zoomStepMinor, zoomMax));
                }
            }

            if (rl.isKeyDown(.up)) {
                if (isShiftDown) {
                    camera.target.y = camera.target.y - moveStepMajor;
                } else {
                    camera.target.y = camera.target.y - moveStepMinor;
                }
            }

            if (rl.isKeyDown(.down)) {
                if (isShiftDown) {
                    camera.target.y = camera.target.y + moveStepMajor;
                } else {
                    camera.target.y = camera.target.y + moveStepMinor;
                }
            }

            if (rl.isKeyDown(.left)) {
                if (isShiftDown) {
                    camera.target.x = camera.target.x - moveStepMajor;
                } else {
                    camera.target.x = camera.target.x - moveStepMinor;
                }
            }

            if (rl.isKeyDown(.right)) {
                if (isShiftDown) {
                    camera.target.x = camera.target.x + moveStepMajor;
                } else {
                    camera.target.x = camera.target.x + moveStepMinor;
                }
            }

            if (rl.isKeyPressed(.left_bracket)) { // '[' Key
                activeStyle = activeStyle.cycle(-1);
                rl.unloadTexture(crosshairTexture);
                crosshairTexture = try createCursorTexture(allocator, activeStyle);
            }
            if (rl.isKeyPressed(.right_bracket)) { // ']' Key
                activeStyle = activeStyle.cycle(1);
                rl.unloadTexture(crosshairTexture);
                crosshairTexture = try createCursorTexture(allocator, activeStyle);
            }

            // Interactivity: Process Zooming relative to the mouse pointer
            const wheel = rl.getMouseWheelMove();
            if (wheel != 0.0) {
                // Find exactly where the mouse pointer points inside Doom's coordinate bounds
                const mouseWorldPosition = rl.getScreenToWorld2D(rl.getMousePosition(), camera);

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
                camera.target.y -= delta.y;
            }

            //------------------------------------------------------------------
            // Draw
            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(rl.Color.black);

            drawWorldGrid(
                camera,
                rl.Color.dark_gray,
                rl.Color.white,
                rl.Color.dark_gray,
            );

            drawWadMap(
                mapLines.items,
                mapThings.items,
                customFont,
                camera,
            );

            drawUi(
                mapIndex + 1,
                mapIndices.len,
                mapLines.items.len,
                customFont,
                camera,
            );

            { // ---------------------------------------------------------------
                const mousePosition = rl.getMousePosition();
                // Screen -> World coordinates
                var worldClickPosition = rl.getScreenToWorld2D(mousePosition, camera);
                // World -> Doom coordinates
                worldClickPosition.y = -worldClickPosition.y;
                var buffer: [256]u8 = undefined;
                const fmtLabel = fmtFixedBuffer(
                    &buffer,
                    "[{d:.0}, {d:.0}]",
                    .{ worldClickPosition.x, worldClickPosition.y },
                );
                drawCrosshair(
                    crosshairTexture,
                    mousePosition,
                    fmtLabel,
                    10,
                    rl.Color.dark_gray,
                );
            }

            //------------------------------------------------------------------
        }
    }
}

////////////////////////////////////////////////////////////////////////////////
