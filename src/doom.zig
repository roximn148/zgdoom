// /////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2026 RoXimn
// This software is released under the MIT License.
// /////////////////////////////////////////////////////////////////////////////
const std = @import("std");
const fout = @import("utils.zig").fout;
const Endian = std.builtin.Endian;
const AutoHashMap = std.hash_map.AutoHashMap;

////////////////////////////////////////////////////////////////////////////////
pub const WadHeader = extern struct {
    const Self = @This();
    magic: [4]u8,
    lumpCount: u32,
    directoryOffset: u32,

    pub fn format(
        self: Self,
        writer: *std.Io.Writer,
    ) !void {
        try writer.print("WAD Header: {s}, Lumps: {d}, Offset: {X:08}h", .{
            self.magic[0..4],
            self.lumpCount,
            self.directoryOffset,
        });
    }
};

// /////////////////////////////////////////////////////////////////////////////
pub const FileLump = extern struct {
    const Self = @This();
    filePosition: u32,
    size: u32,
    name: [8]u8,
    // -------------------------------------------------------------------------
    pub fn cleanName(self: *const Self) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.name, 0) orelse 8;
        return self.name[0..len];
    }
    // -------------------------------------------------------------------------
    pub fn isMap(self: *const Self) bool {
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
    // -------------------------------------------------------------------------
    pub fn format(
        self: Self,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("@{X:08}h {d:>8} '{s}'{s}", .{
            self.filePosition,
            self.size,
            self.cleanName(),
            if (self.isMap()) " *** MAP ***" else "",
        });
    }
};

////////////////////////////////////////////////////////////////////////////////
pub const WadDirectory = extern struct {
    header: WadHeader,
    lumps: [0]FileLump,
};

////////////////////////////////////////////////////////////////////////////////
pub const THINGS_ID = [8]u8{ 0x54, 0x48, 0x49, 0x4E, 0x47, 0x53, 0x00, 0x00 };
pub const TH_FLAG_LEVEL12: u16 = 1 << 0; // 0x0001
pub const TH_FLAG_LEVEL3: u16 = 1 << 1; // 0x0002
pub const TH_FLAG_LEVEL45: u16 = 1 << 2; // 0x0004
pub const TH_FLAG_DEAF: u16 = 1 << 3; // 0x0008
pub const TH_FLAG_MULTIPLAYER: u16 = 1 << 4; // 0x0010

pub const Thing = extern struct {
    const Self = @This();
    x: i16,
    y: i16,
    angle: i16,
    id: i16,
    flags: i16,
    // -------------------------------------------------------------------------
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        if (std.enums.fromInt(ThingType, self.id)) |thingType| {
            try writer.print("{s} [{d}] ", .{ thingType.toString(), self.id });
        } else {
            try writer.print("??? [{d}] ", .{self.id});
        }
        try writer.print("@{d}, {d} <{d} [ ", .{ self.x, self.y, self.angle });
        if ((self.flags & TH_FLAG_LEVEL12) != 0) try writer.print("lv1 lv2 ", .{});
        if ((self.flags & TH_FLAG_LEVEL3) != 0) try writer.print("lv3 ", .{});
        if ((self.flags & TH_FLAG_LEVEL45) != 0) try writer.print("lv4 lv5 ", .{});
        if ((self.flags & TH_FLAG_DEAF) != 0) try writer.print("deaf ", .{});
        if ((self.flags & TH_FLAG_MULTIPLAYER) != 0) try writer.print("multi ", .{});
        try writer.print("]", .{});
    }
};

////////////////////////////////////////////////////////////////////////////////
pub const LINEDEFS_ID = [8]u8{ 0x4C, 0x49, 0x4E, 0x45, 0x44, 0x45, 0x46, 0x53 };
pub const ML_BLOCKING: u16 = 1 << 0; // 0x0001
pub const ML_BLOCKMONSTERS: u16 = 1 << 1; // 0x0002
pub const ML_TWOSIDED: u16 = 1 << 2; // 0x0004
pub const ML_DONTPEGTOP: u16 = 1 << 3; // 0x0008

pub const ML_DONTPEGBOTTOM: u16 = 1 << 4; // 0x0010
pub const ML_SECRET: u16 = 1 << 5; // 0x0020
pub const ML_SOUNDBLOCK: u16 = 1 << 6; // 0x0040
pub const ML_DONTDRAW: u16 = 1 << 7; // 0x0080
pub const ML_MAPPED: u16 = 1 << 8; // 0x0100

pub const LineDef = extern struct {
    const Self = @This();
    vdx1: i16, // Starting Vertex: Starting (X,Y) coordinate
    vdx2: i16, // Ending Vertex: Ending (X,Y) coordinate
    flags: i16, // Flags: Attribute bits
    special: i16, // Linedef type: Special action or behavior
    tag: i16, // Tag: Associates sector(s)/line(s) with the special
    sidenum1: i16, // Front Sidedef
    sidenum2: i16, // Back Sidedef

    // -------------------------------------------------------------------------
    pub fn format(
        self: Self,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{d} -> {d} ", .{ self.vdx1, self.vdx2 });
        try writer.print("F({d}):B({d}) [ ", .{ self.sidenum1, self.sidenum2 });
        if ((self.flags & ML_BLOCKING) != 0) try writer.print("block-player-monsters ", .{});
        if ((self.flags & ML_BLOCKMONSTERS) != 0) try writer.print("block-monsters ", .{});
        if ((self.flags & ML_TWOSIDED) != 0) try writer.print("two-sided ", .{});
        if ((self.flags & ML_DONTPEGTOP) != 0) try writer.print("top-unpegged ", .{});
        if ((self.flags & ML_DONTPEGBOTTOM) != 0) try writer.print("bottom-unpegged ", .{});
        if ((self.flags & ML_SECRET) != 0) try writer.print("secret ", .{});
        if ((self.flags & ML_SOUNDBLOCK) != 0) try writer.print("block-sound ", .{});
        if ((self.flags & ML_DONTDRAW) != 0) try writer.print("no-draw ", .{});
        if ((self.flags & ML_MAPPED) != 0) try writer.print("always-draw ", .{});
        try writer.print("] S[{d}]", .{self.special});
    }
};

////////////////////////////////////////////////////////////////////////////////
pub const SIDEDEFS_ID = [8]u8{ 0x53, 0x49, 0x44, 0x45, 0x44, 0x45, 0x46, 0x53 };
pub const SideDef = extern struct {
    const Self = @This();
    x: i16, // x offset
    y: i16, // y offset
    upper: [8]u8, // Name of upper texture
    lower: [8]u8, // Name of lower texture
    middle: [8]u8, // Name of middle texture
    sector: i16, // Sector number this sidedef 'faces'

    // -------------------------------------------------------------------------
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{d:>4}, {d:<4} ", .{ self.x, self.y });
        try writer.print("U({s}):M({s}):L({s}) ", .{ self.upper, self.middle, self.lower });
        try writer.print("S[{d}]", .{self.sector});
    }
};

////////////////////////////////////////////////////////////////////////////////
pub const VERTEXES_ID = [8]u8{ 0x56, 0x45, 0x52, 0x54, 0x45, 0x58, 0x45, 0x53 };
pub const Vertex = extern struct {
    const Self = @This();
    x: i16, // x position
    y: i16, // y position

    // -------------------------------------------------------------------------
    pub fn format(
        self: Self,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{d:>5}, {d:<5}", .{ self.x, self.y });
    }
};

////////////////////////////////////////////////////////////////////////////////
pub const SEGMENTS_ID = [8]u8{ 0x53, 0x45, 0x47, 0x53, 0x00, 0x00, 0x00, 0x00 };
pub const Segment = extern struct {
    const Self = @This();
    v1: i16, // Starting vertex number
    v2: i16, // Ending vertex number
    angle: i16, // Angle, full circle is -32768 to 32767
    lineDef: i16, // LineDef number
    direction: i16, // Direction: 0 (same as lineDef) or 1 (opposite of lineDef)
    offset: i16, // Offset: distance along lineDef to start of seg

    // -------------------------------------------------------------------------
    pub fn format(
        self: Self,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{d:>5} -> {d:<5} < {d:>6} L[{d}] D[{d}] :{d}", .{
            self.v1,      self.v2,        self.angle,
            self.lineDef, self.direction, self.offset,
        });
    }
};

////////////////////////////////////////////////////////////////////////////////
pub const SUBSECTORS_ID = [8]u8{ 0x53, 0x53, 0x45, 0x43, 0x54, 0x4F, 0x52, 0x53 };
pub const SubSector = extern struct {
    const Self = @This();
    count: i16, // Seg count
    first: i16, // First seg number

    // -------------------------------------------------------------------------
    pub fn format(
        self: Self,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("S[{d}] L1({d})", .{ self.count, self.first });
    }
};

////////////////////////////////////////////////////////////////////////////////
pub const NODES_ID = [8]u8{ 0x4E, 0x4F, 0x44, 0x45, 0x53, 0x00, 0x00, 0x00 };
pub const BoundingBox = extern struct { top: i16, bottom: i16, left: i16, right: i16 };
pub const Node = extern struct {
    const Self = @This();
    x: i16, // x coordinate of partition line start
    y: i16, // y coordinate of partition line start
    dx: i16, // Change in x from start to end of partition line
    dy: i16, // Change in y from start to end of partition line
    rightBBox: BoundingBox, // Right bounding box
    leftBBox: BoundingBox, // Left bounding box
    rChild: u16, // Right child
    lChild: u16, // Left child

    // -------------------------------------------------------------------------
    pub fn format(
        self: Self,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{d:>5}, {d:<5} ", .{ self.x, self.y });
        try writer.print("+[{d:>4}, {d:<4}] ", .{ self.dx, self.dy });

        try writer.print("rBB[{d} {d} {d} {d}] ", .{
            self.rightBBox.top,
            self.rightBBox.right,
            self.rightBBox.bottom,
            self.rightBBox.left,
        });
        try writer.print("lBB[{d} {d} {d} {d}] ", .{
            self.leftBBox.top,
            self.leftBBox.right,
            self.leftBBox.bottom,
            self.leftBBox.left,
        });

        var isSubNode = (self.rChild & (1 << 15) == 0);
        if (isSubNode) {
            try writer.print("R-SN", .{});
        } else {
            try writer.print("R-SS", .{});
        }
        try writer.print("[{d}] ", .{self.rChild & 0x7FFF});

        isSubNode = (self.lChild & (1 << 15) == 0);
        if (isSubNode) {
            try writer.print("L-SN", .{});
        } else {
            try writer.print("L-SS", .{});
        }
        try writer.print("[{d}]", .{self.lChild & 0x7FFF});
    }
};

////////////////////////////////////////////////////////////////////////////////
pub const SECTORS_ID = [8]u8{ 0x53, 0x45, 0x43, 0x54, 0x4F, 0x52, 0x53, 0x00 };
pub const Sector = extern struct {
    const Self = @This();
    floorHeight: i16,
    ceilingHeight: i16,
    floorTexture: [8]u8,
    ceilingTexture: [8]u8,
    light: i16, // Light level
    special: i16, // Special Type
    tag: i16, // Tag number

    // -------------------------------------------------------------------------
    pub fn format(
        self: Self,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("floor h:{d:<4}, T:'{s}' ", .{ self.floorHeight, self.floorTexture });
        try writer.print("ceiling h:{d:<4}, T:'{s}' ", .{ self.ceilingHeight, self.ceilingTexture });
        try writer.print("light:{d}, special:{d}, tag:{d}", .{ self.light, self.special, self.tag });
    }
};

////////////////////////////////////////////////////////////////////////////////
pub const REJECT_ID = [8]u8{ 0x52, 0x45, 0x4A, 0x45, 0x43, 0x54, 0x00, 0x00 };
pub const BLOCKMAP_ID = [8]u8{ 0x42, 0x4C, 0x4F, 0x43, 0x4B, 0x4D, 0x41, 0x50 };

pub const ThingType = enum(i16) {
    // Monsters ----------------------------------------------------------------
    Arachnotron = 0x0044,
    ArchVile = 0x0040,
    BaronOfHell = 0x0BBB,
    Cacodemon = 0x0BBD,
    CommanderKeen = 0x0048,
    Cyberdemon = 0x0010,
    Demon = 0x0BBA,
    HeavyWeaponDude = 0x0041,
    HellKnight = 0x0045,
    Imp = 0x0BB9,
    LostSoul = 0x0BBE,
    Mancubus = 0x0043,
    PainElemental = 0x0047,
    Revenant = 0x0042,
    ShotgunGuy = 0x0009,
    Spectre = 0x003A,
    Spiderdemon = 0x0007,
    WolfensteinSs = 0x0054,
    Zombieman = 0x0BBC,

    // Artifact items ----------------------------------------------------------
    Supercharge = 0x07DD,
    ArmorBonus = 0x07DF,
    Berserk = 0x07E7,
    ComputerAreaMap = 0x07EA,
    HealthBonus = 0x07DE,
    Invulnerability = 0x07E6,
    LightAmplificationVisor = 0x07FD,
    Megasphere = 0x0053,
    PartialInvisibility = 0x07E8,

    // Weapons -----------------------------------------------------------------
    Bfg9000 = 0x07D6,
    Chaingun = 0x07D2,
    Chainsaw = 0x07D5,
    PlasmaGun = 0x07D4,
    RocketLauncher = 0x07D3,
    Shotgun = 0x07D1,
    SuperShotgun = 0x0052,

    // Ammunition --------------------------------------------------------------
    FourShotgunShells = 0x07D8,
    BoxOfBullets = 0x0800,
    BoxOfRockets = 0x07FE,
    BoxOfShotgunShells = 0x0801,
    Clip = 0x07D7,
    EnergyCell = 0x07FF,
    EnergyCellPack = 0x0011,
    Rocket = 0x07DA,

    // Power-ups ---------------------------------------------------------------
    Armor = 0x07E2,
    Backpack = 0x0008,
    Medikit = 0x07DC,
    Megaarmor = 0x07E3,
    RadiationShieldingSuit = 0x07E9,
    Stimpack = 0x07DB,

    // Keys --------------------------------------------------------------------
    BlueKeycard = 0x0005,
    BlueSkullKey = 0x0028,
    RedKeycard = 0x000D,
    RedSkullKey = 0x0026,
    YellowKeycard = 0x0006,
    YellowSkullKey = 0x0027,

    // Other -------------------------------------------------------------------
    Player1Start = 0x0001,
    Player2Start = 0x0002,
    Player3Start = 0x0003,
    Player4Start = 0x0004,
    DeathMatchStart = 0x000B,
    TeleportLanding = 0x000E,
    SpawnSpot = 0x0057,
    RomeroHead = 0x0058,
    MonsterSpawner = 0x0059,

    // Decorations -------------------------------------------------------------
    BloodyMess1 = 0x000A,
    BloodyMess2 = 0x000C,
    DeadCacodemon = 0x0016,
    DeadDemon = 0x0015,
    DeadFormerHuman = 0x0012,
    DeadFormerSergeant = 0x0013,
    DeadImp = 0x0014,
    DeadLostSoulInvisible = 0x0017,
    DeadPlayer = 0x000F,
    HangingLeg = 0x003E,
    HangingPairOfLegs = 0x003C,
    HangingVictimArmsOut = 0x003B,
    HangingVictimOneLegged = 0x003D,
    HangingVictimTwitching = 0x003F,
    PoolOfBlood1 = 0x004F,
    PoolOfBlood2 = 0x0050,
    PoolOfBloodAndFlesh = 0x0018,
    PoolOfBrains = 0x0051,
    Candle = 0x0022,

    // Obstacles ---------------------------------------------------------------
    BrownStump = 0x002F,
    BurningBarrel = 0x0046,
    BurntTree = 0x002B,
    Candelabra = 0x0023,
    EvilEye = 0x0029,
    ExplodingBarrel = 0x07F3,
    FiveSkullsShishKebab = 0x001C,
    FloatingSkull = 0x002A,
    FloorLamp = 0x07EC,
    HangingLegObstacle = 0x0035,
    HangingPairOfLegsObstacle = 0x0034,
    HangingTorsoBrainRemoved = 0x004E,
    HangingTorsoLookingDown = 0x004B,
    HangingTorsoLookingUp = 0x004D,
    HangingTorsoOpenSkull = 0x004C,
    HangingVictimArmsOutObstacle = 0x0032,
    HangingVictimGutsAndBrainRemoved = 0x004A,
    HangingVictimGutsRemoved = 0x0049,
    HangingVictimOneLeggedObstacle = 0x0033,
    HangingVictimTwitchingObstacle = 0x0031,
    ImpaledHuman = 0x0019,
    LargeBrownTree = 0x0036,
    PileOfSkullsAndCandles = 0x001D,
    ShortBlueFirestick = 0x0037,
    ShortGreenFirestick = 0x0038,
    ShortGreenPillar = 0x001F,
    ShortGreenPillarWithBeatingHeart = 0x0024,
    ShortRedFirestick = 0x0039,
    ShortRedPillar = 0x0021,
    ShortRedPillarWithSkull = 0x0025,
    ShortTechnoFloorLamp = 0x0056,
    SkullOnAPole = 0x001B,
    TallBlueFirestick = 0x002C,
    TallGreenFirestick = 0x002D,
    TallGreenPillar = 0x001E,
    TallRedFirestick = 0x002E,
    TallRedPillar = 0x0020,
    TallTechnoColumn = 0x0030,
    TallTechnoFloorLamp = 0x0055,
    TwitchingImpaledHuman = 0x001A,

    /// Returns the String representation for the enum tag.
    pub fn toString(self: ThingType) []const u8 {
        return switch (self) {
            // Monsters
            .Arachnotron => "Arachnotron",
            .ArchVile => "Archvile",
            .BaronOfHell => "BaronOfHell",
            .Cacodemon => "Cacodemon",
            .CommanderKeen => "CommanderKeen",
            .Cyberdemon => "Cyberdemon",
            .Demon => "Demon",
            .HeavyWeaponDude => "HeavyWeaponDude",
            .HellKnight => "HellKnight",
            .Imp => "Imp",
            .LostSoul => "LostSoul",
            .Mancubus => "Mancubus",
            .PainElemental => "PainElemental",
            .Revenant => "Revenant",
            .ShotgunGuy => "ShotgunGuy",
            .Spectre => "Spectre",
            .Spiderdemon => "Spiderdemon",
            .WolfensteinSs => "WolfensteinSS",
            .Zombieman => "Zombieman",

            // Artifact items
            .Supercharge => "Supercharge",
            .ArmorBonus => "ArmorBonus",
            .Berserk => "Berserk",
            .ComputerAreaMap => "ComputerAreaMap",
            .HealthBonus => "HealthBonus",
            .Invulnerability => "Invulnerability",
            .LightAmplificationVisor => "LightAmplificationVisor",
            .Megasphere => "Megasphere",
            .PartialInvisibility => "PartialInvisibility",

            // Weapons
            .Bfg9000 => "BFG9000",
            .Chaingun => "Chaingun",
            .Chainsaw => "Chainsaw",
            .PlasmaGun => "PlasmaGun",
            .RocketLauncher => "RocketLauncher",
            .Shotgun => "Shotgun",
            .SuperShotgun => "SuperShotgun",

            // Ammunition
            .FourShotgunShells => "FourShotgunShells",
            .BoxOfBullets => "BoxOfBullets",
            .BoxOfRockets => "BoxOfRockets",
            .BoxOfShotgunShells => "BoxOfShotgunShells",
            .Clip => "Clip",
            .EnergyCell => "EnergyCell",
            .EnergyCellPack => "EnergyCellPack",
            .Rocket => "Rocket",

            // Power-ups
            .Armor => "Armor",
            .Backpack => "Backpack",
            .Medikit => "Medikit",
            .Megaarmor => "Megaarmor",
            .RadiationShieldingSuit => "RadiationShieldingSuit",
            .Stimpack => "Stimpack",

            // Keys
            .BlueKeycard => "BlueKeycard",
            .BlueSkullKey => "BlueSkullKey",
            .RedKeycard => "RedKeycard",
            .RedSkullKey => "RedSkullKey",
            .YellowKeycard => "YellowKeycard",
            .YellowSkullKey => "YellowSkullKey",

            // Other
            .Player1Start => "Player1",
            .Player2Start => "Player2",
            .Player3Start => "Player3",
            .Player4Start => "Player4",
            .DeathMatchStart => "DeathMatchStart",
            .TeleportLanding => "TeleportLanding",
            .SpawnSpot => "SpawnSpot",
            .RomeroHead => "RomeroHead",
            .MonsterSpawner => "MonsterSpawner",

            // Decorations
            .BloodyMess1 => "BloodyMess",
            .BloodyMess2 => "BloodyMess2",
            .DeadCacodemon => "DeadCacodemon",
            .DeadDemon => "DeadDemon",
            .DeadFormerHuman => "DeadFormerHuman",
            .DeadFormerSergeant => "DeadFormerSergeant",
            .DeadImp => "DeadImp",
            .DeadLostSoulInvisible => "DeadLostSoul",
            .DeadPlayer => "DeadPlayer",
            .HangingLeg => "HangingLeg",
            .HangingPairOfLegs => "HangingPairOfLegs",
            .HangingVictimArmsOut => "HangingVictim-ArmsOut",
            .HangingVictimOneLegged => "HangingVictim-OneLegged",
            .HangingVictimTwitching => "HangingVictim-Twitching",
            .PoolOfBlood1 => "PoolOfBlood1",
            .PoolOfBlood2 => "PoolOfBlood2",
            .PoolOfBloodAndFlesh => "PoolOfBloodAndFlesh",
            .PoolOfBrains => "PoolOfBrains",
            .Candle => "Candle",

            // Obstacles
            .BrownStump => "BrownStump",
            .BurningBarrel => "BurningBarrel",
            .BurntTree => "BurntTree",
            .Candelabra => "Candelabra",
            .EvilEye => "EvilEye",
            .ExplodingBarrel => "ExplodingBarrel",
            .FiveSkullsShishKebab => "FiveSkullsShishKebab",
            .FloatingSkull => "FloatingSkull",
            .FloorLamp => "FloorLamp",
            .HangingLegObstacle => "HangingLegObstacle",
            .HangingPairOfLegsObstacle => "HangingPairOfLegsObstacle",
            .HangingTorsoBrainRemoved => "HangingTorsoBrainRemoved",
            .HangingTorsoLookingDown => "HangingTorsoLookingDown",
            .HangingTorsoLookingUp => "HangingTorsoLookingUp",
            .HangingTorsoOpenSkull => "HangingTorsoOpenSkull",
            .HangingVictimArmsOutObstacle => "HangingVictimArmsOutObstacle",
            .HangingVictimGutsAndBrainRemoved => "HangingVictimGutsAndBrainRemoved",
            .HangingVictimGutsRemoved => "HangingVictimGutsRemoved",
            .HangingVictimOneLeggedObstacle => "HangingVictimOneLeggedObstacle",
            .HangingVictimTwitchingObstacle => "HangingVictimTwitchingObstacle",
            .ImpaledHuman => "ImpaledHuman",
            .LargeBrownTree => "LargeBrownTree",
            .PileOfSkullsAndCandles => "PileOfSkullsAndCandles",
            .ShortBlueFirestick => "ShortBlueFirestick",
            .ShortGreenFirestick => "ShortGreenFirestick",
            .ShortGreenPillar => "ShortGreenPillar",
            .ShortGreenPillarWithBeatingHeart => "ShortGreenPillarWithBeatingHeart",
            .ShortRedFirestick => "ShortRedFirestick",
            .ShortRedPillar => "ShortRedPillar",
            .ShortRedPillarWithSkull => "ShortRedPillarWithSkull",
            .ShortTechnoFloorLamp => "ShortTechnoFloorLamp",
            .SkullOnAPole => "SkullOnAPole",
            .TallBlueFirestick => "TallBlueFirestick",
            .TallGreenFirestick => "TallGreenFirestick",
            .TallGreenPillar => "TallGreenPillar",
            .TallRedFirestick => "TallRedFirestick",
            .TallRedPillar => "TallRedPillar",
            .TallTechnoColumn => "TallTechnoColumn",
            .TallTechnoFloorLamp => "TallTechnoFloorLamp",
            .TwitchingImpaledHuman => "TwitchingImpaledHuman",
        };
    }
};

////////////////////////////////////////////////////////////////////////////////
pub fn readWadDirectory(
    allocator: std.mem.Allocator,
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
    const wadHeader = try reader.interface.takeStruct(WadHeader, Endian.little);
    // 1. Calculate total memory needed
    const totalSize = @sizeOf(WadDirectory) + (@sizeOf(FileLump) * wadHeader.lumpCount);
    // 2. Allocate raw aligned memory
    const buffer: []align(4) u8 = try allocator.allocWithOptions(
        u8,
        totalSize,
        std.mem.Alignment.@"4",
        null,
    );
    // 3. Cast to target struct pointer
    var directory: *WadDirectory = @ptrCast(buffer.ptr);
    // 4. Access the elements
    directory.header = wadHeader;
    const lumps: []FileLump = @as([*]FileLump, @ptrCast(&directory.lumps))[0..directory.header.lumpCount];
    try reader.seekTo(wadHeader.directoryOffset);
    for (0..wadHeader.lumpCount) |i| {
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
/// for destroying it using `allocator.free()`.
///
/// Errors:
/// - `error.OutOfMemory` if the heap allocation fails.
pub fn getMapIndexes(allocator: std.mem.Allocator, lumps: []FileLump) ![]usize {
    // Determine the array size and allocate
    const count: u32 = getMapCount(lumps);
    var indices = try allocator.alloc(usize, count);

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
    allocator: std.mem.Allocator,
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
    const things = try allocator.alloc(Thing, N);

    try reader.seekTo(thingsLump.filePosition);
    for (0..things.len) |j| {
        things[j] = try reader.interface.takeStruct(Thing, Endian.little);
    }
    return things;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readLineDefs(
    allocator: std.mem.Allocator,
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
    const lineDefs = try allocator.alloc(LineDef, N);

    try reader.seekTo(lineDefsLump.filePosition);
    for (0..lineDefs.len) |j| {
        lineDefs[j] = try reader.interface.takeStruct(LineDef, Endian.little);
    }
    return lineDefs;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readSideDefs(
    allocator: std.mem.Allocator,
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
    const sideDefs = try allocator.alloc(SideDef, N);

    try reader.seekTo(sideDefsLump.filePosition);
    for (0..sideDefs.len) |j| {
        sideDefs[j] = try reader.interface.takeStruct(SideDef, Endian.little);
    }
    return sideDefs;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readVertexes(
    allocator: std.mem.Allocator,
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
    const vertexes = try allocator.alloc(Vertex, N);

    try reader.seekTo(vertexesLump.filePosition);
    for (0..vertexes.len) |j| {
        vertexes[j] = try reader.interface.takeStruct(Vertex, Endian.little);
    }
    return vertexes;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readSegments(
    allocator: std.mem.Allocator,
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
    const segments = try allocator.alloc(Segment, N);

    try reader.seekTo(segmentsLump.filePosition);
    for (0..segments.len) |j| {
        segments[j] = try reader.interface.takeStruct(Segment, Endian.little);
    }
    return segments;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readSubSectors(
    allocator: std.mem.Allocator,
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
    const subSectors = try allocator.alloc(SubSector, N);

    try reader.seekTo(subSectorsLump.filePosition);
    for (0..subSectors.len) |j| {
        subSectors[j] = try reader.interface.takeStruct(SubSector, Endian.little);
    }
    return subSectors;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readNodes(
    allocator: std.mem.Allocator,
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
    const nodes = try allocator.alloc(Node, N);

    try reader.seekTo(nodesLump.filePosition);
    for (0..nodes.len) |j| {
        nodes[j] = try reader.interface.takeStruct(Node, Endian.little);
    }
    return nodes;
}

////////////////////////////////////////////////////////////////////////////////
pub fn readSectors(
    allocator: std.mem.Allocator,
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
    const sectors = try allocator.alloc(Sector, N);

    try reader.seekTo(sectorsLump.filePosition);
    for (0..sectors.len) |j| {
        sectors[j] = try reader.interface.takeStruct(Sector, Endian.little);
    }
    return sectors;
}

////////////////////////////////////////////////////////////////////////////////
pub fn dumpWad(
    allocator: std.mem.Allocator,
    ofile: std.Io.File,
    io: std.Io,
    ifile: []const u8,
    verbose: bool,
) !void {
    // Header + Directory ------------------------------------------------------
    const wadData = try readWadDirectory(allocator, io, ifile);
    defer allocator.free(wadData);

    var wad: *WadDirectory = @ptrCast(wadData.ptr);
    const lumps: []FileLump = @as(
        [*]FileLump,
        @ptrCast(&wad.lumps),
    )[0..wad.header.lumpCount];

    // WAD Header --------------------------------------------------------------
    fout(ofile, io, "{f}\n", .{wad.header});

    // Lumps -------------------------------------------------------------------
    for (0..wad.header.lumpCount) |i| {
        fout(ofile, io, "Lump{d: <6}{f}\n", .{ i, lumps[i] });
    }

    // Maps --------------------------------------------------------------------
    fout(ofile, io, "*** {d} Maps found\n", .{getMapCount(lumps)});
    const indices = try getMapIndexes(allocator, lumps);
    defer allocator.free(indices);
    for (indices, 0..) |index, i| {
        fout(ofile, io, "Map{d:<2}: {s} (Lump{d})\n", .{
            i,
            lumps[index].cleanName(),
            index,
        });
    }

    for (0..wad.header.lumpCount) |i| {
        // THINGS --------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &THINGS_ID)) {
            const things: []Thing = try readThings(allocator, io, &lumps[i], ifile);
            defer allocator.free(things);

            fout(
                ofile,
                io,
                "*** {d} Things at {X:08}\n",
                .{ things.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (0..things.len) |j| {
                    fout(ofile, io, "Thing{d:<4} {f}\n", .{ j, things[j] });
                }
            }
        } else

        // LINEDEFS ------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &LINEDEFS_ID)) {
            const lineDefs: []LineDef = try readLineDefs(allocator, io, &lumps[i], ifile);
            defer allocator.free(lineDefs);

            fout(
                ofile,
                io,
                "*** {d} LineDefs at {X:08}\n",
                .{ lineDefs.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (lineDefs, 0..) |lineDef, j| {
                    fout(ofile, io, "LineDef{d:<4} {f}\n", .{ j, lineDef });
                }
            }
        } else

        // SIDEDEFS ------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &SIDEDEFS_ID)) {
            const sideDefs: []SideDef = try readSideDefs(allocator, io, &lumps[i], ifile);
            defer allocator.free(sideDefs);

            fout(
                ofile,
                io,
                "*** {d} SideDefs at {X:08}\n",
                .{ sideDefs.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (sideDefs, 0..) |sideDef, j| {
                    fout(ofile, io, "SideDef{d:<4} {f}\n", .{ j, sideDef });
                }
            }
        } else

        // VERTEXES ------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &VERTEXES_ID)) {
            const vertexes: []Vertex = try readVertexes(allocator, io, &lumps[i], ifile);
            defer allocator.free(vertexes);

            fout(
                ofile,
                io,
                "*** {d} Vertexes at {X:08}\n",
                .{ vertexes.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (vertexes, 0..) |vertex, j| {
                    fout(ofile, io, "Vertex{d:<4} {f}\n", .{ j, vertex });
                }
            }
        } else

        // SEGS ----------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &SEGMENTS_ID)) {
            const segments: []Segment = try readSegments(allocator, io, &lumps[i], ifile);
            defer allocator.free(segments);

            fout(
                ofile,
                io,
                "*** {d} Segs at {X:08}\n",
                .{ segments.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (segments, 0..) |segment, j| {
                    fout(ofile, io, "Seg{d:<4} {f}\n", .{ j, segment });
                }
            }
        } else

        // SSECTORS ------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &SUBSECTORS_ID)) {
            const subSectors: []SubSector = try readSubSectors(allocator, io, &lumps[i], ifile);
            defer allocator.free(subSectors);

            fout(
                ofile,
                io,
                "*** {d} SubSectors at {X:08}\n",
                .{ subSectors.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (subSectors, 0..) |subSector, j| {
                    fout(ofile, io, "SubSector{d:<4} {f}\n", .{ j, subSector });
                }
            }
        } else

        // NODES ---------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &NODES_ID)) {
            const nodes: []Node = try readNodes(allocator, io, &lumps[i], ifile);
            defer allocator.free(nodes);

            fout(
                ofile,
                io,
                "*** {d} Nodes at {X:08}\n",
                .{ nodes.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (nodes, 0..) |node, j| {
                    fout(ofile, io, "Node{d:<4} {f}\n", .{ j, node });
                }
            }
        } else

        // SECTORS -------------------------------------------------------------
        if (std.mem.eql(u8, &lumps[i].name, &SECTORS_ID)) {
            const sectors: []Sector = try readSectors(allocator, io, &lumps[i], ifile);
            defer allocator.free(sectors);

            fout(
                ofile,
                io,
                "*** {d} Sectors at {X:08}\n",
                .{ sectors.len, lumps[i].filePosition },
            );
            if (verbose) {
                for (sectors, 0..) |sector, j| {
                    fout(ofile, io, "Sector{d:<4} {f}\n", .{ j, sector });
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
