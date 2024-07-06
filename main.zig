const Argparse = @This();

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

args: []const []const u8 = undefined,
arguments: std.StringHashMapUnmanaged([]const u8) = .{},
positionals: std.ArrayListUnmanaged([]const u8) = .{},
allocator: Allocator,
params: []const ParamDesc,
error_key: ?[]const u8 = null,

pub var desc_max_length: usize = 50;

pub const Error = error{
    UnknownArgument,
    ExpectedValue,
    UnexpectedValue,
};

pub const ParamDesc = struct {
    long: []const u8,
    short: ?u8 = null,
    need_value: bool = false,
    desc: ?[]const u8 = null,

    fn getPrefixLength(pd: *const ParamDesc) usize {
        // length of -x,_ is 4
        var len: usize = if (pd.short) |_| 4 else 0;
        // + 2 is for --
        len += pd.long.len + 2;

        return len;
    }
};

pub fn init(allocator: Allocator, params: []const ParamDesc) Argparse {
    return .{
        .allocator = allocator,
        .params = params,
    };
}

pub fn deinit(self: *Argparse) void {
    self.arguments.deinit(self.allocator);
    self.positionals.deinit(self.allocator);
}

pub fn renderError(self: *Argparse, writer: anytype, err: Error) !void {
    switch (err) {
        error.UnknownArgument => try writer.print("unknown argument: '--{s}'\n", .{self.error_key.?}),
        error.ExpectedValue => try writer.print("expected value for key '{s}'\n", .{self.error_key.?}),
        error.UnexpectedValue => try writer.print("key '{s}' does not take value\n", .{self.error_key.?}),
    }
}

pub fn renderHelp(arg: *Argparse, writer: anytype) !void {
    var max_len: usize = 0;
    for (arg.params) |param| {
        const len = param.getPrefixLength();
        if (len > max_len)
            max_len = len;
    }

    for (arg.params) |param| {
        try writer.writeAll("  ");
        if (param.short) |short|
            try writer.print("-{c}, ", .{short});

        try writer.print("--{s}", .{param.long});

        // Minimum of 2 space
        try writer.writeByteNTimes(' ', (max_len - param.getPrefixLength()) + 2);

        if (param.desc) |desc| {
            const parts = @divFloor(desc.len, desc_max_length);
            {
                // TODO: make parts on word boundary rather than arbitarily
                var i: usize = 0;
                while (i <= parts) : (i += 1) {
                    const start = i * desc_max_length;
                    const end = @min(desc.len, (i + 1) * desc_max_length);
                    try writer.writeAll(desc[start..end]);
                    _ = try writer.writeByte('\n');
                    if (i != parts)
                        try writer.writeByteNTimes(' ', max_len + 4);
                }
            }
        }
    }
}

fn next(self: *Argparse, index: *usize) ?[]const u8 {
    if (index.* < self.args.len) {
        index.* += 1;
        return self.args[index.* - 1];
    }

    return null;
}

fn getDescFromLong(self: *Argparse, long: []const u8) Error!ParamDesc {
    for (self.params) |param| {
        if (mem.eql(u8, param.long, long)) {
            return param;
        }
    }

    self.error_key = long;
    return error.UnknownArgument;
}

fn getDescFromShort(self: *Argparse, short: []const u8) Error!ParamDesc {
    for (self.params) |param| if (param.short) |p_short| {
        if (p_short == short[0]) {
            return param;
        }
    };

    self.error_key = short;
    return error.UnknownArgument;
}

inline fn makeValue(self: *Argparse, key: []const u8, value: ?[]const u8, i: *usize, desc: ParamDesc) Error![]const u8 {
    return blk: {
        if (desc.need_value) {
            break :blk value orelse self.next(i) orelse {
                self.error_key = key;
                return error.ExpectedValue;
            };
        } else if (value != null) {
            self.error_key = key;
            return error.UnexpectedValue;
        } else break :blk "true";
    };
}

pub fn parse(self: *Argparse, args: []const []const u8) (Error || std.mem.Allocator.Error)!void {
    self.args = args;

    var i: usize = 0;
    while (i < args.len) {
        var key = self.next(&i).?;
        var value: ?[]const u8 = null;

        if (mem.startsWith(u8, key, "--")) {
            if (mem.eql(u8, key, "--")) {
                while (self.next(&i)) |pos|
                    try self.positionals.append(self.allocator, pos);
                return;
            }

            if (mem.indexOf(u8, key, "=")) |pos| {
                value = key[(pos + 1)..];
                key = key[0..pos];
            }

            const key_name = key[2..];
            const desc = try self.getDescFromLong(key_name);

            const val = try self.makeValue(key, value, &i, desc);
            try self.arguments.put(self.allocator, key_name, val);
        } else if (mem.startsWith(u8, key, "-")) {
            if (mem.indexOf(u8, key, "=")) |pos| {
                value = key[(pos + 1)..];
            }

            var id: usize = 1;
            while (id < key.len) : (id += 1) {
                const key_name = key[id .. id + 1];
                const desc = try self.getDescFromShort(key_name);
                const has_value = id + 1 < key.len and key[id + 1] == '=';

                const val = blk: {
                    if (desc.need_value) {
                        if (!has_value and id + 1 < key.len) {
                            value = key[id + 1 ..];
                            id += value.?.len;
                        }
                        break :blk value;
                    } else {
                        break :blk if (has_value) value else null;
                    }
                };

                const val_final = try self.makeValue(key_name, val, &i, desc);
                try self.arguments.put(self.allocator, desc.long, val_final);

                if (has_value) break;
            }
        } else {
            try self.positionals.append(self.allocator, key);
        }
    }
}

const testing = @import("std").testing;
const expectStrings = testing.expectEqualStrings;
const expectError = testing.expectError;

test "long param" {
    const params = &[_]ParamDesc{
        .{ .long = "simple_long" },
        .{ .long = "long_with_value", .need_value = true },
        .{ .long = "another_long_with_value", .need_value = true },
    };

    const args = &[_][]const u8{
        "--simple_long",
        "--long_with_value",
        "10",
        "--another_long_with_value=20",
    };

    var argparse = Argparse.init(std.testing.allocator, params);
    defer argparse.deinit();

    argparse.parse(args) catch unreachable;

    try expectStrings("true", argparse.arguments.get("simple_long").?);
    try expectStrings("10", argparse.arguments.get("long_with_value").?);
    try expectStrings("20", argparse.arguments.get("another_long_with_value").?);
}

test "short param" {
    const params = &[_]ParamDesc{
        .{ .long = "simple_short", .short = 's' },
        .{ .long = "short_with_value", .short = 'v', .need_value = true },
        .{ .long = "another_short_with_value", .short = 'a', .need_value = true },
        .{ .long = "no_value", .short = 'n' },
        .{ .long = "yes_value", .short = 'y', .need_value = true },
    };

    const args = &[_][]const u8{ "-s", "-v", "2", "-a3", "-ny4" };

    var argparse = Argparse.init(std.testing.allocator, params);
    defer argparse.deinit();

    argparse.parse(args) catch unreachable;

    try expectStrings("true", argparse.arguments.get("simple_short").?);
    try expectStrings("2", argparse.arguments.get("short_with_value").?);
    try expectStrings("3", argparse.arguments.get("another_short_with_value").?);
    try expectStrings("true", argparse.arguments.get("no_value").?);
    try expectStrings("4", argparse.arguments.get("yes_value").?);
}

test "unknown argument" {
    const params = &[_]ParamDesc{};

    const args = &[_][]const u8{"-e"};

    var argparse = Argparse.init(std.testing.allocator, params);
    defer argparse.deinit();

    try expectError(error.UnknownArgument, argparse.parse(args));
}

test "expected value" {
    const params = &[_]ParamDesc{.{ .long = "value", .need_value = true }};

    const args = &[_][]const u8{"--value"};

    var argparse = Argparse.init(std.testing.allocator, params);
    defer argparse.deinit();

    try expectError(error.ExpectedValue, argparse.parse(args));
}

test "unexpected value" {
    const params = &[_]ParamDesc{.{ .long = "value" }};

    const args = &[_][]const u8{"--value=10"};

    var argparse = Argparse.init(std.testing.allocator, params);
    defer argparse.deinit();

    try expectError(error.UnexpectedValue, argparse.parse(args));
}
