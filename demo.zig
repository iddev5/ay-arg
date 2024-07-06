const std = @import("std");
const Argparse = @import("ay-arg");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    // Set a custom value
    Argparse.desc_max_length = 60;

    const params = &[_]Argparse.ParamDesc{
        .{ .long = "help", .short = 'h', .desc = "Prints this help message" },
        .{ .long = "foo", .short = 'e', .desc = "This is foo without value. This is meant to be a very long line exceeding the limit for one line. Now that we are doing it, better make it three lines" },
        .{ .long = "test", .short = 's', .need_value = true, .desc = "This is test with value" },
    };

    var argparse = Argparse.init(allocator, params[0..]);
    defer argparse.deinit();

    argparse.parse(args[1..]) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => |e| return try argparse.renderError(std.io.getStdErr().writer(), e),
    };

    if (argparse.arguments.contains("help")) {
        try argparse.renderHelp(std.io.getStdOut().writer());
        return;
    }

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
