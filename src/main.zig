const std = @import("std");
const cmark_bind_zig = @import("cmark_bind_zig");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
