// /////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2026 RoXimn
// This software is released under the MIT License.
// /////////////////////////////////////////////////////////////////////////////
const std = @import("std");
const fout = @import("utils.zig").fout;
const Endian = std.builtin.Endian;
const AutoHashMap = std.hash_map.AutoHashMap;

////////////////////////////////////////////////////////////////////////////////
pub const WadInfo = extern struct {
    magic: [4]u8,
    lumpCount: u32,
    directoryOffset: u32,
};

////////////////////////////////////////////////////////////////////////////////
pub const FileLump = extern struct {
    const Self = @This();
    filePosition: u32,
    size: u32,
    name: [8]u8,

    fn cleanName(self: *const Self) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.name, 0) orelse 8;
        return self.name[0..len];
    }

    fn isMap(self: *const Self) bool {
        const name = self.cleanName();
        // std.debug.print("'{s}' -> '{any}'\n", .{ self.name, name });
        if (name.len == 4) {
            // Matches E1M1 style pattern
            return (name[0] == 'E' and std.ascii.isDigit(name[1]) and
                name[2] == 'M' and std.ascii.isDigit(name[3]));
        }
        if (name.len >= 5 and std.mem.startsWith(u8, name, "MAP")) {
            // Matches MAP01 style pattern
            for (name[3..]) |c| {
                if (!std.ascii.isDigit(c)) return false;
            }
            return true;
        }
        return false;
    }
};

////////////////////////////////////////////////////////////////////////////////
pub const WadDirectory = extern struct {
    header: WadInfo,
    lumps: [0]FileLump,
};

////////////////////////////////////////////////////////////////////////////////
pub const THINGS_ID = [8]u8{ 0x54, 0x48, 0x49, 0x4E, 0x47, 0x53, 0x00, 0x00 };
pub const Thing = extern struct {
    x: i16,
    y: i16,
    angle: i16,
    id: i16,
    flags: i16,
};

////////////////////////////////////////////////////////////////////////////////
pub const LINEDEFS_ID = [8]u8{ 0x4C, 0x49, 0x4E, 0x45, 0x44, 0x45, 0x46, 0x53 };
pub const LineDef = extern struct {
    vdx1: i16, // Starting Vertex: Starting (X,Y) coordinate
    vdx2: i16, // Ending Vertex: Ending (X,Y) coordinate
    flags: i16, // Flags: Attribute bits
    special: i16, // Linedef type: Special action or behavior
    tag: i16, // Tag: Associates sector(s)/line(s) with the special
    sidenum1: i16, // Front Sidedef
    sidenum2: i16, // Back Sidedef
};

////////////////////////////////////////////////////////////////////////////////
pub const SIDEDEFS_ID = [8]u8{ 0x53, 0x49, 0x44, 0x45, 0x44, 0x45, 0x46, 0x53 };
pub const SideDef = extern struct {
    x: i16, // x offset
    y: i16, // y offset
    upper: [8]u8, // Name of upper texture
    lower: [8]u8, // Name of lower texture
    middle: [8]u8, // Name of middle texture
    sector: i16, // Sector number this sidedef 'faces'
};

////////////////////////////////////////////////////////////////////////////////
pub const VERTEXES_ID = [8]u8{ 0x56, 0x45, 0x52, 0x54, 0x45, 0x58, 0x45, 0x53 };
pub const Vertex = extern struct {
    x: i16, // x position
    y: i16, // y position
};

////////////////////////////////////////////////////////////////////////////////
pub const SEGMENTS_ID = [8]u8{ 0x53, 0x45, 0x47, 0x53, 0x00, 0x00, 0x00, 0x00 };
pub const Segment = extern struct {
    v1: i16, // Starting vertex number
    v2: i16, // Ending vertex number
    angle: i16, // Angle, full circle is -32768 to 32767
    lineDef: i16, // LineDef number
    direction: i16, // Direction: 0 (same as lineDef) or 1 (opposite of lineDef)
    offset: i16, // Offset: distance along lineDef to start of seg
};

////////////////////////////////////////////////////////////////////////////////
pub const SUBSECTORS_ID = [8]u8{ 0x53, 0x53, 0x45, 0x43, 0x54, 0x4F, 0x52, 0x53 };
pub const SubSector = extern struct {
    count: i16, // Seg count
    first: i16, // First seg number
};

////////////////////////////////////////////////////////////////////////////////
pub const NODES_ID = [8]u8{ 0x4E, 0x4F, 0x44, 0x45, 0x53, 0x00, 0x00, 0x00 };
pub const BoundingBox = extern struct { top: i16, bottom: i16, left: i16, right: i16 };
pub const Node = extern struct {
    x: i16, // x coordinate of partition line start
    y: i16, // y coordinate of partition line start
    dx: i16, // Change in x from start to end of partition line
    dy: i16, // Change in y from start to end of partition line
    rightBBox: BoundingBox, // Right bounding box
    leftBBox: BoundingBox, // Left bounding box
    rChild: u16, // Right child
    lChild: u16, // Left child
};

////////////////////////////////////////////////////////////////////////////////
pub const SECTORS_ID = [8]u8{ 0x53, 0x45, 0x43, 0x54, 0x4F, 0x52, 0x53, 0x00 };
pub const Sector = extern struct {
    floorHeight: i16,
    ceilingHeight: i16,
    floorTexture: [8]u8,
    ceilingTexture: [8]u8,
    light: i16, // Light level
    special: i16, // Special Type
    tag: i16, // Tag number
};

////////////////////////////////////////////////////////////////////////////////
pub const REJECT_ID = [8]u8{ 0x52, 0x45, 0x4A, 0x45, 0x43, 0x54, 0x00, 0x00 };
pub const BLOCKMAP_ID = [8]u8{ 0x42, 0x4C, 0x4F, 0x43, 0x4B, 0x4D, 0x41, 0x50 };

////////////////////////////////////////////////////////////////////////////////
pub const ML_BLOCKING: u16 = 1 << 0; // 0x0001
pub const ML_BLOCKMONSTERS: u16 = 1 << 1; // 0x0002
pub const ML_TWOSIDED: u16 = 1 << 2; // 0x0004
pub const ML_DONTPEGTOP: u16 = 1 << 3; // 0x0008

pub const ML_DONTPEGBOTTOM: u16 = 1 << 4; // 0x0010
pub const ML_SECRET: u16 = 1 << 5; // 0x0020
pub const ML_SOUNDBLOCK: u16 = 1 << 6; // 0x0040
pub const ML_DONTDRAW: u16 = 1 << 7; // 0x0080
pub const ML_MAPPED: u16 = 1 << 8; // 0x0100

pub fn lineDefFlagsToString(gpa: std.mem.Allocator, flags: i16) ![]const u8 {
    var activeFlags = try std.ArrayList([]const u8).initCapacity(
        gpa,
        16,
    );
    defer activeFlags.deinit(gpa);

    if ((flags & ML_BLOCKING) != 0) try activeFlags.append(gpa, "block-player-monsters");
    if ((flags & ML_BLOCKMONSTERS) != 0) try activeFlags.append(gpa, "block-monsters");
    if ((flags & ML_TWOSIDED) != 0) try activeFlags.append(gpa, "two-sided");
    if ((flags & ML_DONTPEGTOP) != 0) try activeFlags.append(gpa, "top-unpegged");
    if ((flags & ML_DONTPEGBOTTOM) != 0) try activeFlags.append(gpa, "bottom-unpegged");
    if ((flags & ML_SECRET) != 0) try activeFlags.append(gpa, "secret");
    if ((flags & ML_SOUNDBLOCK) != 0) try activeFlags.append(gpa, "block-sound");
    if ((flags & ML_DONTDRAW) != 0) try activeFlags.append(gpa, "no-draw");
    if ((flags & ML_MAPPED) != 0) try activeFlags.append(gpa, "always-draw");

    if (activeFlags.items.len == 0) {
        try activeFlags.append(gpa, "none");
    }

    return try std.mem.join(
        gpa,
        ", ",
        activeFlags.items,
    );
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpWadInfo(file: std.Io.File, io: std.Io, wadInfo: *const WadInfo) void {
    fout(file, io, "WAD Info\n", .{});
    fout(file, io, "  Identification:   {s}\n", .{wadInfo.magic[0..4]});
    fout(file, io, "  Number of Lumps:  {d}\n", .{wadInfo.lumpCount});
    fout(file, io, "  Directory Offset: {X:08}h\n", .{wadInfo.directoryOffset});
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpFileLump(file: std.Io.File, io: std.Io, fileLump: *const FileLump, i: usize) void {
    fout(file, io, "Lump{d:<4} ", .{i});
    fout(file, io, "@{X:08}h ", .{fileLump.filePosition});
    fout(file, io, "{d:>6} ", .{fileLump.size});
    fout(file, io, "'{s}'{s}\n", .{
        fileLump.cleanName(),
        if (fileLump.isMap()) "    *- MAP -*" else "",
    });
}

////////////////////////////////////////////////////////////////////////////////
pub const TH_FLAG_LEVEL12: u16 = 1 << 0; // 0x0001
pub const TH_FLAG_LEVEL3: u16 = 1 << 1; // 0x0002
pub const TH_FLAG_LEVEL45: u16 = 1 << 2; // 0x0004
pub const TH_FLAG_DEAF: u16 = 1 << 3; // 0x0008
pub const TH_FLAG_MULTIPLAYER: u16 = 1 << 4; // 0x0010

pub fn thingFlagsToString(gpa: std.mem.Allocator, flags: i16) ![]const u8 {
    var activeFlags = try std.ArrayList([]const u8).initCapacity(
        gpa,
        16,
    );
    defer activeFlags.deinit(gpa);

    if ((flags & TH_FLAG_LEVEL12) != 0) try activeFlags.append(gpa, "lv1, lv2");
    if ((flags & TH_FLAG_LEVEL3) != 0) try activeFlags.append(gpa, "lv3");
    if ((flags & TH_FLAG_LEVEL45) != 0) try activeFlags.append(gpa, "lv4, lv5");
    if ((flags & TH_FLAG_DEAF) != 0) try activeFlags.append(gpa, "deaf");
    if ((flags & TH_FLAG_MULTIPLAYER) != 0) try activeFlags.append(gpa, "multi");

    if (activeFlags.items.len == 0) {
        try activeFlags.append(gpa, "none");
    }

    return try std.mem.join(
        gpa,
        ", ",
        activeFlags.items,
    );
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpThing(
    file: std.Io.File,
    io: std.Io,
    gpa: std.mem.Allocator,
    thing: *const Thing,
    i: usize,
    thingNames: AutoHashMap(i16, []const u8),
) !void {
    const namedFlags = try thingFlagsToString(gpa, thing.flags);
    defer gpa.free(namedFlags);

    fout(file, io, "Thing{d:<4} ", .{i});
    const name = thingNames.get(thing.id);
    if (name) |v| {
        fout(file, io, "{s} [{d}] ", .{ v, thing.id });
    } else {
        fout(file, io, "{d} ", .{thing.id});
    }
    fout(file, io, "@{d}, {d} <{d} ", .{ thing.x, thing.y, thing.angle });
    fout(file, io, "({s})\n", .{namedFlags});
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpLineDef(
    file: std.Io.File,
    io: std.Io,
    gpa: std.mem.Allocator,
    lineDef: *const LineDef,
    i: usize,
) !void {
    const namedFlags = try lineDefFlagsToString(gpa, lineDef.flags);
    defer gpa.free(namedFlags);

    fout(file, io, "LineDef [{d}]: ", .{i});
    fout(file, io, "{d} -> {d} ", .{ lineDef.vdx1, lineDef.vdx2 });
    fout(file, io, "F({d}):B({d}) ", .{ lineDef.sidenum1, lineDef.sidenum2 });
    fout(file, io, "({s}) S[{d}]\n", .{ namedFlags, lineDef.special });
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpSideDef(
    file: std.Io.File,
    io: std.Io,
    sideDef: *const SideDef,
    i: usize,
) void {
    fout(file, io, "SideDef [{d}]: ", .{i});
    fout(file, io, "{d}, {d} ", .{ sideDef.x, sideDef.y });
    fout(file, io, "U({s}):M({s}):L({s}) ", .{ sideDef.upper, sideDef.middle, sideDef.lower });
    fout(file, io, "S[{d}]\n", .{sideDef.sector});
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpVertex(file: std.Io.File, io: std.Io, vertex: *const Vertex, i: usize) void {
    fout(file, io, "Vertex [{d}]: {d}, {d}\n", .{ i, vertex.x, vertex.y });
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpSegment(file: std.Io.File, io: std.Io, segment: *const Segment, i: usize) void {
    fout(file, io, "Seg [{d}]: ", .{i});
    fout(file, io, "{d} -> {d} ", .{ segment.v1, segment.v2 });
    fout(file, io, "<{d} ", .{segment.angle});
    fout(file, io, "L[{d}] D[{d}] :{d}\n", .{
        segment.lineDef,
        segment.direction,
        segment.offset,
    });
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpSubSector(file: std.Io.File, io: std.Io, subSector: *const SubSector, i: usize) void {
    fout(file, io, "SubSector [{d}]: S[{d}] L1({d})\n", .{
        i,
        subSector.count,
        subSector.first,
    });
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpNode(file: std.Io.File, io: std.Io, node: *const Node, i: usize) void {
    fout(file, io, "Node [{d}]: ", .{i});
    fout(file, io, "{d}, {d} ", .{ node.x, node.y });
    fout(file, io, "+[{d}, {d}] ", .{ node.dx, node.dy });

    fout(file, io, "rBB[{d} {d} {d} {d}] ", .{
        node.rightBBox.top,
        node.rightBBox.right,
        node.rightBBox.bottom,
        node.rightBBox.left,
    });
    fout(file, io, "lBB[{d} {d} {d} {d}] ", .{
        node.leftBBox.top,
        node.leftBBox.right,
        node.leftBBox.bottom,
        node.leftBBox.left,
    });

    var isSubNode = (node.rChild & (1 << 15) == 0);
    if (isSubNode) {
        fout(file, io, "R-SN", .{});
    } else {
        fout(file, io, "R-SS", .{});
    }
    fout(file, io, "[{d}] ", .{node.rChild & 0x7FFF});

    isSubNode = (node.lChild & (1 << 15) == 0);
    if (isSubNode) {
        fout(file, io, "L-SN", .{});
    } else {
        fout(file, io, "L-SS", .{});
    }
    fout(file, io, "[{d}]\n", .{node.lChild & 0x7FFF});
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpSector(file: std.Io.File, io: std.Io, sector: *const Sector, i: usize) void {
    fout(file, io, "Sector [{d}]: ", .{i});
    fout(file, io, "floor h:{d}, T:'{s}' ", .{ sector.floorHeight, sector.floorTexture });
    fout(file, io, "ceiling h:{d}, T:'{s}' ", .{ sector.ceilingHeight, sector.ceilingTexture });
    fout(file, io, "light:{d}, special:{d}, tag:{d}\n", .{ sector.light, sector.special, sector.tag });
}

////////////////////////////////////////////////////////////////////////////////
/// Allocates and initializes a map linking Doom map entity ("Thing") IDs to string names.
///
/// The resulting hash map provides user readable names for the things.
///
/// ### Memory Ownership
/// The caller owns the returned `AutoHashMap` and must free its associated internal storage
/// by calling `.deinit()` on it when it is no longer needed. The string slice values
/// (e.g., `"Arachnotron"`) are static string literals stored in the binary data
/// segment and do not need to be freed.
///
/// ### Arguments
/// * `allocator` - The allocator used to provision the map's internal dynamic table buckets.
///
/// ### Errors
/// * `error.OutOfMemory` - Returned if the allocator fails to reserve memory while initializing
///   the map or populating it via `.put()`.
pub fn createThingsNameMap(gpa: std.mem.Allocator) !AutoHashMap(i16, []const u8) {
    var thingsMap = AutoHashMap(i16, []const u8).init(gpa);
    errdefer thingsMap.deinit();

    // Monsters ----------------------------------------------------------------
    try thingsMap.put(0x0044, "Arachnotron");
    try thingsMap.put(0x0040, "Arch-vile");
    try thingsMap.put(0x0BBB, "Baron of Hell");
    try thingsMap.put(0x0BBD, "Cacodemon");
    try thingsMap.put(0x0048, "Commander Keen");
    try thingsMap.put(0x0010, "Cyberdemon");
    try thingsMap.put(0x0BBA, "Demon");
    try thingsMap.put(0x0041, "Heavy weapon dude");
    try thingsMap.put(0x0045, "Hell knight");
    try thingsMap.put(0x0BB9, "Imp");
    try thingsMap.put(0x0BBE, "Lost soul");
    try thingsMap.put(0x0043, "Mancubus");
    try thingsMap.put(0x0047, "Pain elemental");
    try thingsMap.put(0x0042, "Revenant");
    try thingsMap.put(0x0009, "Shotgun guy");
    try thingsMap.put(0x003A, "Spectre");
    try thingsMap.put(0x0007, "Spiderdemon");
    try thingsMap.put(0x0054, "Wolfenstein SS");
    try thingsMap.put(0x0BBC, "Zombieman");

    // Artifact items ----------------------------------------------------------
    try thingsMap.put(0x07DD, "Supercharge");
    try thingsMap.put(0x07DF, "Armor Bonus");
    try thingsMap.put(0x07E7, "Berserk");
    try thingsMap.put(0x07EA, "Computer Area Map");
    try thingsMap.put(0x07DE, "Health Bonus");
    try thingsMap.put(0x07E6, "Invulnerability");
    try thingsMap.put(0x07FD, "Light Amplification Visor");
    try thingsMap.put(0x0053, "Megasphere");
    try thingsMap.put(0x07E8, "Partial Invisibility");

    // Weapons -----------------------------------------------------------------
    try thingsMap.put(0x07D6, "BFG9000");
    try thingsMap.put(0x07D2, "Chaingun");
    try thingsMap.put(0x07D5, "Chainsaw");
    try thingsMap.put(0x07D4, "Plasma Gun");
    try thingsMap.put(0x07D3, "Rocket Launcher");
    try thingsMap.put(0x07D1, "Shotgun");
    try thingsMap.put(0x0052, "Super Shotgun");

    // Ammunition --------------------------------------------------------------
    try thingsMap.put(0x07D8, "Four Shotgun Shells");
    try thingsMap.put(0x0800, "Box of Bullets");
    try thingsMap.put(0x07FE, "Box of Rockets");
    try thingsMap.put(0x0801, "Box of Shotgun Shells");
    try thingsMap.put(0x07D7, "Clip");
    try thingsMap.put(0x07FF, "Energy Cell");
    try thingsMap.put(0x0011, "Energy Cell Pack");
    try thingsMap.put(0x07DA, "Rocket");

    // Power-ups ---------------------------------------------------------------
    try thingsMap.put(0x07E2, "Armor");
    try thingsMap.put(0x0008, "Backpack");
    try thingsMap.put(0x07DC, "Medikit");
    try thingsMap.put(0x07E3, "Megaarmor");
    try thingsMap.put(0x07E9, "Radiation Shielding Suit");
    try thingsMap.put(0x07DB, "Stimpack");

    // Keys --------------------------------------------------------------------

    try thingsMap.put(0x0005, "Blue Keycard");
    try thingsMap.put(0x0028, "Blue Skull Key");
    try thingsMap.put(0x000D, "Red Keycard");
    try thingsMap.put(0x0026, "Red Skull Key");
    try thingsMap.put(0x0006, "Yellow Keycard");
    try thingsMap.put(0x0027, "Yellow Skull Key");

    // Other -------------------------------------------------------------------
    try thingsMap.put(0x0001, "Player 1 Start");
    try thingsMap.put(0x0002, "Player 2 Start");
    try thingsMap.put(0x0003, "Player 3 Start");
    try thingsMap.put(0x0004, "Player 4 Start");
    try thingsMap.put(0x000B, "DeathMatch Start");
    try thingsMap.put(0x000E, "Teleport Landing");
    try thingsMap.put(0x0057, "Spawn Spot");
    try thingsMap.put(0x0058, "Romero's Head");
    try thingsMap.put(0x0059, "Monster Spawner");

    // Decorations -------------------------------------------------------------
    try thingsMap.put(0x002D, "Small Mushroom 3");

    // Obstacles ---------------------------------------------------------------

    return thingsMap;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readWadDirectory(
    gpa: std.mem.Allocator,
    io: std.Io,
    ifile: []const u8,
) ![]align(4) u8 {
    // File --------------------------------------------------------------------
    var cwd = std.Io.Dir.cwd();
    var wadFile = try cwd.openFile(
        io,
        ifile,
        .{ .mode = .read_only },
    );
    defer wadFile.close(io);

    // File Reader -------------------------------------------------------------
    var readBuffer: [4096]u8 = undefined;
    var reader = wadFile.reader(io, &readBuffer);

    // WAD Header --------------------------------------------------------------
    try reader.seekTo(0);
    const wadInfo = try reader.interface.takeStruct(WadInfo, Endian.little);
    // 1. Calculate total memory needed
    const totalSize = @sizeOf(WadDirectory) + (@sizeOf(FileLump) * wadInfo.lumpCount);
    // 2. Allocate raw aligned memory
    const buffer: []align(4) u8 = try gpa.allocWithOptions(
        u8,
        totalSize,
        std.mem.Alignment.@"4",
        null,
    );
    // 3. Cast to target struct pointer
    var directory: *WadDirectory = @ptrCast(buffer.ptr);
    // 4. Access the elements
    directory.header = wadInfo;
    const lumps: []FileLump = @as([*]FileLump, @ptrCast(&directory.lumps))[0..directory.header.lumpCount];
    try reader.seekTo(wadInfo.directoryOffset);
    for (0..wadInfo.lumpCount) |i| {
        lumps[i] = try reader.interface.takeStruct(FileLump, Endian.little);
    }
    return buffer;
}

////////////////////////////////////////////////////////////////////////////////
pub fn getMapCount(lumps: []FileLump) u32 {
    var count: u32 = 0;
    for (lumps) |lump| {
        if (lump.isMap()) {
            count += 1;
        }
    }
    return count;
}

////////////////////////////////////////////////////////////////////////////////
/// Scans an array of lumps to identify and extract the array indices
/// of all map marker lumps.
///
/// This function dynamically allocates memory for the returned slice.
/// The caller takes full ownership of the returned slice and is responsible
/// for destroying it using `gpa.free()`.
///
/// Errors:
/// - `error.OutOfMemory` if the heap allocation fails.
pub fn getMapIndexes(gpa: std.mem.Allocator, lumps: []FileLump) ![]usize {
    // Determine the array size and allocate
    const count: u32 = getMapCount(lumps);
    var indices = try gpa.alloc(usize, count);

    // Cursor to track position in indices array
    var idx: usize = 0;

    for (lumps, 0..) |lump, i| {
        // If the current lump is a map marker,
        //  save this index and move to next index storing location
        if (lump.isMap()) {
            indices[idx] = i;
            idx += 1;
        }
    }

    // Explicitly return the populated slice, transfer memory ownership
    return indices;
}

////////////////////////////////////////////////////////////////////////////////
const WadError = error{
    InvalidLump,
};

////////////////////////////////////////////////////////////////////////////////
pub fn readThings(
    gpa: std.mem.Allocator,
    io: std.Io,
    thingsLump: *const FileLump,
    ifile: []const u8,
) ![]Thing {
    if (!std.mem.eql(u8, &thingsLump.name, &THINGS_ID)) {
        // std.debug.print("Expected '{s}'': Actual '{s}'", .{ THINGS_ID, thingsLump.name });
        return error.InvalidLump;
    }
    // File --------------------------------------------------------------------
    var wadFile = try std.Io.Dir.cwd().openFile(
        io,
        ifile,
        .{ .mode = .read_only },
    );
    defer wadFile.close(io);

    // File Reader -------------------------------------------------------------
    var readBuffer: [4096]u8 = undefined;
    var reader = wadFile.reader(io, &readBuffer);

    // Things Lump -------------------------------------------------------------
    const N = thingsLump.size / @sizeOf(Thing);
    const things = try gpa.alloc(Thing, N);

    try reader.seekTo(thingsLump.filePosition);
    for (0..things.len) |j| {
        things[j] = try reader.interface.takeStruct(Thing, Endian.little);
    }
    return things;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readLineDefs(
    gpa: std.mem.Allocator,
    io: std.Io,
    lineDefsLump: *const FileLump,
    ifile: []const u8,
) ![]LineDef {
    if (!std.mem.eql(u8, &lineDefsLump.name, &LINEDEFS_ID)) {
        return error.InvalidLump;
    }
    // File --------------------------------------------------------------------
    var wadFile = try std.Io.Dir.cwd().openFile(
        io,
        ifile,
        .{ .mode = .read_only },
    );
    defer wadFile.close(io);

    // File Reader -------------------------------------------------------------
    var readBuffer: [4096]u8 = undefined;
    var reader = wadFile.reader(io, &readBuffer);

    // LineDefs Lump -----------------------------------------------------------
    const N = lineDefsLump.size / @sizeOf(LineDef);
    const lineDefs = try gpa.alloc(LineDef, N);

    try reader.seekTo(lineDefsLump.filePosition);
    for (0..lineDefs.len) |j| {
        lineDefs[j] = try reader.interface.takeStruct(LineDef, Endian.little);
    }
    return lineDefs;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readSideDefs(
    gpa: std.mem.Allocator,
    io: std.Io,
    sideDefsLump: *const FileLump,
    ifile: []const u8,
) ![]SideDef {
    if (!std.mem.eql(u8, &sideDefsLump.name, &SIDEDEFS_ID)) {
        return error.InvalidLump;
    }
    // File --------------------------------------------------------------------
    var wadFile = try std.Io.Dir.cwd().openFile(
        io,
        ifile,
        .{ .mode = .read_only },
    );
    defer wadFile.close(io);

    // File Reader -------------------------------------------------------------
    var readBuffer: [4096]u8 = undefined;
    var reader = wadFile.reader(io, &readBuffer);

    // SideDefs Lump -----------------------------------------------------------
    const N = sideDefsLump.size / @sizeOf(SideDef);
    const sideDefs = try gpa.alloc(SideDef, N);

    try reader.seekTo(sideDefsLump.filePosition);
    for (0..sideDefs.len) |j| {
        sideDefs[j] = try reader.interface.takeStruct(SideDef, Endian.little);
    }
    return sideDefs;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readVertexes(
    gpa: std.mem.Allocator,
    io: std.Io,
    vertexesLump: *const FileLump,
    ifile: []const u8,
) ![]Vertex {
    if (!std.mem.eql(u8, &vertexesLump.name, &VERTEXES_ID)) {
        return error.InvalidLump;
    }
    // File --------------------------------------------------------------------
    var wadFile = try std.Io.Dir.cwd().openFile(
        io,
        ifile,
        .{ .mode = .read_only },
    );
    defer wadFile.close(io);

    // File Reader -------------------------------------------------------------
    var readBuffer: [4096]u8 = undefined;
    var reader = wadFile.reader(io, &readBuffer);

    // Vertexes Lump -----------------------------------------------------------
    const N = vertexesLump.size / @sizeOf(Vertex);
    const vertexes = try gpa.alloc(Vertex, N);

    try reader.seekTo(vertexesLump.filePosition);
    for (0..vertexes.len) |j| {
        vertexes[j] = try reader.interface.takeStruct(Vertex, Endian.little);
    }
    return vertexes;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readSegments(
    gpa: std.mem.Allocator,
    io: std.Io,
    segmentsLump: *const FileLump,
    ifile: []const u8,
) ![]Segment {
    if (!std.mem.eql(u8, &segmentsLump.name, &SEGMENTS_ID)) {
        return error.InvalidLump;
    }
    // File --------------------------------------------------------------------
    var wadFile = try std.Io.Dir.cwd().openFile(
        io,
        ifile,
        .{ .mode = .read_only },
    );
    defer wadFile.close(io);

    // File Reader -------------------------------------------------------------
    var readBuffer: [4096]u8 = undefined;
    var reader = wadFile.reader(io, &readBuffer);

    // Vertexes Lump -----------------------------------------------------------
    const N = segmentsLump.size / @sizeOf(Segment);
    const segments = try gpa.alloc(Segment, N);

    try reader.seekTo(segmentsLump.filePosition);
    for (0..segments.len) |j| {
        segments[j] = try reader.interface.takeStruct(Segment, Endian.little);
    }
    return segments;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readSubSectors(
    gpa: std.mem.Allocator,
    io: std.Io,
    subSectorsLump: *const FileLump,
    ifile: []const u8,
) ![]SubSector {
    if (!std.mem.eql(u8, &subSectorsLump.name, &SUBSECTORS_ID)) {
        return error.InvalidLump;
    }
    // File --------------------------------------------------------------------
    var wadFile = try std.Io.Dir.cwd().openFile(
        io,
        ifile,
        .{ .mode = .read_only },
    );
    defer wadFile.close(io);

    // File Reader -------------------------------------------------------------
    var readBuffer: [4096]u8 = undefined;
    var reader = wadFile.reader(io, &readBuffer);

    // Vertexes Lump -----------------------------------------------------------
    const N = subSectorsLump.size / @sizeOf(SubSector);
    const subSectors = try gpa.alloc(SubSector, N);

    try reader.seekTo(subSectorsLump.filePosition);
    for (0..subSectors.len) |j| {
        subSectors[j] = try reader.interface.takeStruct(SubSector, Endian.little);
    }
    return subSectors;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readNodes(
    gpa: std.mem.Allocator,
    io: std.Io,
    nodesLump: *const FileLump,
    ifile: []const u8,
) ![]Node {
    if (!std.mem.eql(u8, &nodesLump.name, &NODES_ID)) {
        return error.InvalidLump;
    }
    // File --------------------------------------------------------------------
    var wadFile = try std.Io.Dir.cwd().openFile(
        io,
        ifile,
        .{ .mode = .read_only },
    );
    defer wadFile.close(io);

    // File Reader -------------------------------------------------------------
    var readBuffer: [4096]u8 = undefined;
    var reader = wadFile.reader(io, &readBuffer);

    // Vertexes Lump -----------------------------------------------------------
    const N = nodesLump.size / @sizeOf(Node);
    const nodes = try gpa.alloc(Node, N);

    try reader.seekTo(nodesLump.filePosition);
    for (0..nodes.len) |j| {
        nodes[j] = try reader.interface.takeStruct(Node, Endian.little);
    }
    return nodes;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readSectors(
    gpa: std.mem.Allocator,
    io: std.Io,
    sectorsLump: *const FileLump,
    ifile: []const u8,
) ![]Sector {
    if (!std.mem.eql(u8, &sectorsLump.name, &SECTORS_ID)) {
        return error.InvalidLump;
    }
    // File --------------------------------------------------------------------
    var wadFile = try std.Io.Dir.cwd().openFile(
        io,
        ifile,
        .{ .mode = .read_only },
    );
    defer wadFile.close(io);

    // File Reader -------------------------------------------------------------
    var readBuffer: [4096]u8 = undefined;
    var reader = wadFile.reader(io, &readBuffer);

    // Vertexes Lump -----------------------------------------------------------
    const N = sectorsLump.size / @sizeOf(Sector);
    const sectors = try gpa.alloc(Sector, N);

    try reader.seekTo(sectorsLump.filePosition);
    for (0..sectors.len) |j| {
        sectors[j] = try reader.interface.takeStruct(Sector, Endian.little);
    }
    return sectors;
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpWad(
    gpa: std.mem.Allocator,
    ofile: std.Io.File,
    io: std.Io,
    ifile: []const u8,
    verbose: bool,
) !void {
    // Header + Directory ------------------------------------------------------
    const wadData = try readWadDirectory(gpa, io, ifile);
    defer gpa.free(wadData);

    var wad: *WadDirectory = @ptrCast(wadData.ptr);
    const lumps: []FileLump = @as(
        [*]FileLump,
        @ptrCast(&wad.lumps),
    )[0..wad.header.lumpCount];

    // WAD Header --------------------------------------------------------------
    dumpWadInfo(ofile, io, &wad.header);

    // Lumps -------------------------------------------------------------------
    for (0..wad.header.lumpCount) |i| {
        dumpFileLump(ofile, io, &lumps[i], i);
    }

    // Maps --------------------------------------------------------------------
    fout(
        ofile,
        io,
        "*** {d} Maps found\n",
        .{getMapCount(lumps)},
    );
    const indices = try getMapIndexes(gpa, lumps);
    defer gpa.free(indices);
    for (indices, 0..) |index, i| {
        fout(
            ofile,
            io,
            "Map{d:<2}: {s}\n",
            .{ i, lumps[index].name },
        );
    }

    for (0..wad.header.lumpCount) |i| {
        // THINGS --------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &THINGS_ID)) {
            const things: []Thing = try readThings(gpa, io, &lumps[i], ifile);
            defer gpa.free(things);

            fout(
                ofile,
                io,
                "*** {d} Things at {X:08}\n",
                .{ things.len, lumps[i].filePosition },
            );
            if (verbose) {
                var thingsMap = try createThingsNameMap(gpa);
                defer thingsMap.deinit();
                for (0..things.len) |j| {
                    try dumpThing(ofile, io, gpa, &things[j], j, thingsMap);
                }
            }
        } else

        // LINEDEFS ------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &LINEDEFS_ID)) {
            const lineDefs: []LineDef = try readLineDefs(gpa, io, &lumps[i], ifile);
            defer gpa.free(lineDefs);

            fout(
                ofile,
                io,
                "*** {d} LineDefs at {X:08}\n",
                .{ lineDefs.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (0..lineDefs.len) |j| {
                    try dumpLineDef(ofile, io, gpa, &lineDefs[j], j);
                }
            }
        } else

        // SIDEDEFS ------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &SIDEDEFS_ID)) {
            const sideDefs: []SideDef = try readSideDefs(gpa, io, &lumps[i], ifile);
            defer gpa.free(sideDefs);

            fout(
                ofile,
                io,
                "*** {d} SideDefs at {X:08}\n",
                .{ sideDefs.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (0..sideDefs.len) |j| {
                    dumpSideDef(ofile, io, &sideDefs[j], j);
                }
            }
        } else

        // VERTEXES ------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &VERTEXES_ID)) {
            const vertexes: []Vertex = try readVertexes(gpa, io, &lumps[i], ifile);
            defer gpa.free(vertexes);

            fout(
                ofile,
                io,
                "*** {d} Vertexes at {X:08}\n",
                .{ vertexes.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (0..vertexes.len) |j| {
                    dumpVertex(ofile, io, &vertexes[j], j);
                }
            }
        } else

        // SEGS ----------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &SEGMENTS_ID)) {
            const segments: []Segment = try readSegments(gpa, io, &lumps[i], ifile);
            defer gpa.free(segments);

            fout(
                ofile,
                io,
                "*** {d} Segs at {X:08}\n",
                .{ segments.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (0..segments.len) |j| {
                    dumpSegment(ofile, io, &segments[j], j);
                }
            }
        } else

        // SSECTORS ------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &SUBSECTORS_ID)) {
            const subSectors: []SubSector = try readSubSectors(gpa, io, &lumps[i], ifile);
            defer gpa.free(subSectors);

            fout(
                ofile,
                io,
                "*** {d} SubSectors at {X:08}\n",
                .{ subSectors.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (0..subSectors.len) |j| {
                    dumpSubSector(ofile, io, &subSectors[j], j);
                }
            }
        } else

        // NODES ---------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &NODES_ID)) {
            const nodes: []Node = try readNodes(gpa, io, &lumps[i], ifile);
            defer gpa.free(nodes);

            fout(
                ofile,
                io,
                "*** {d} Nodes at {X:08}\n",
                .{ nodes.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (0..nodes.len) |j| {
                    dumpNode(ofile, io, &nodes[j], j);
                }
            }
        } else

        // SECTORS -------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &SECTORS_ID)) {
            const sectors: []Sector = try readSectors(gpa, io, &lumps[i], ifile);
            defer gpa.free(sectors);

            fout(
                ofile,
                io,
                "*** {d} Sectors at {X:08}\n",
                .{ sectors.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (0..sectors.len) |j| {
                    dumpSector(ofile, io, &sectors[j], j);
                }
            }
        } else

        // REJECT --------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &REJECT_ID)) {
            fout(ofile, io, "*** RejectMap {d} bytes at {X:08}\n", .{
                lumps[i].size,
                lumps[i].filePosition,
            });
        } else

        // BLOCKMAP ------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &BLOCKMAP_ID)) {
            fout(ofile, io, "*** BlockMap {d} bytes at {X:08}\n", .{
                lumps[i].size,
                lumps[i].filePosition,
            });
        }
    }
}

////////////////////////////////////////////////////////////////////////////////
