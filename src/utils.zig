// /////////////////////////////////////////////////////////////////////////////
//  Copyright (c) 2026 RoXimn
// This software is released under the MIT License.
// /////////////////////////////////////////////////////////////////////////////
const std = @import("std");

////////////////////////////////////////////////////////////////////////////////
pub fn fout(
    file: std.Io.File,
    io: std.Io,
    comptime fmt: []const u8,
    params: anytype,
) void {
    var buffer: [2048]u8 = undefined;
    const formatted = std.fmt.bufPrint(
        &buffer,
        fmt,
        params,
    ) catch |err| switch (err) {
        else => {
            return;
        },
    };

    for (formatted) |*char| {
        if (char.* == 0) {
            char.* = ' ';
        }
    }

    file.writeStreamingAll(
        io,
        formatted,
    ) catch |err| switch (err) {
        else => {},
    };
}

////////////////////////////////////////////////////////////////////////////////
