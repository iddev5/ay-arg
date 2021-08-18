// Example run: zig run test.zig -- -test=value -hi hello -justflag
const std = @import("std");
const ArgParse = @import("ay_arg.zig").ArgParse;

pub fn main() !void {
    const allocator = std.testing.allocator;

    var args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    var argparse = ArgParse.init(args[1..]);
    defer argparse.free();

    var list = try argparse.parse(allocator);
    defer list.deinit();

    var iter = list.iterator();
    while (iter.next()) |entry| {
        const k = entry.key_ptr;
        const v = entry.value_ptr;
        std.debug.print("{s} = {s}\n", .{ k.*, v.* });
    }
}
