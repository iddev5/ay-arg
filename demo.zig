const std = @import("std");
const Argparse = @import("ay-arg");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    const params = &[_]Argparse.ParamDesc{
        .{ .long = "foo", .short = 'e' },
        .{ .long = "test", .short = 's', .need_value = true },
    };

    var argparse = Argparse.init(allocator, params[0..]);
    defer argparse.deinit();

    try argparse.parse(args[1..]);

    var iter = argparse.arguments.iterator();
    while (iter.next()) |entry| {
        const k = entry.key_ptr;
        const v = entry.value_ptr;
        std.debug.print("{s} = {s}\n", .{ k.*, v.* });
    }

    for (argparse.positionals.items) |item| {
        std.debug.print("{s}\n", .{item});
    }
}
