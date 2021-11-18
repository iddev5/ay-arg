const AyArgparse = @This();

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

args: [][]u8 = undefined,
arguments: std.StringHashMapUnmanaged([]const u8) = .{},
positionals: std.ArrayListUnmanaged([]const u8) = .{},
allocator: *Allocator,
params: []const ParamDesc,

pub const ParamDesc = struct {
    long: []const u8,
    short: ?[]const u8 = null,
    need_value: bool = false,
};

pub fn init(allocator: *Allocator, params: []const ParamDesc) AyArgparse {
    return .{
        .allocator = allocator,
        .params = params,
    };
}

pub fn deinit(self: *AyArgparse) void {
    self.arguments.deinit(self.allocator);
    self.positionals.deinit(self.allocator);
}

fn next(self: *AyArgparse, index: *usize) ?[]const u8 {
    if (index.* < self.args.len) {
        index.* += 1;
        return self.args[index.* - 1];
    }

    return null;
}

fn getDescFromLong(self: *AyArgparse, long: []const u8) ParamDesc {
    for (self.params) |param| {
        if (mem.eql(u8, param.long, long)) {
            return param;
        }
    }

    unreachable; // TODO;
}

fn getDescFromShort(self: *AyArgparse, short: []const u8) ParamDesc {
    for (self.params) |param| if (param.short) |p_short| {
        if (mem.eql(u8, p_short, short)) {
            return param;
        }
    };

    unreachable; // TODO;
}

inline fn makeValue(self: *AyArgparse, key: []const u8, value: ?[]const u8, i: *usize, desc: ParamDesc) ![]const u8 {
    return blk: {
        if (desc.need_value) {
            const res = value orelse self.next(i) orelse {
                std.debug.print("expected value for key '{s}'\n", .{key});
                return error.ArgparseError;
            };
            if (mem.startsWith(u8, res, "-")) {
                std.debug.print("key '{s}' was followed by another key '{s}' while value was expected\n", .{ key, res });
                return error.ArgparseError;
            }
            break :blk res;
        } else if (value != null) {
            std.debug.print("found unexpected value '{s}' for key '{s}'\n", .{ value.?, key });
            return error.ArgparseError;
        } else break :blk "true";
    };
}

pub fn parse(self: *AyArgparse, args: [][]u8) !void {
    self.args = args;

    var i: usize = 0;
    while (i < args.len) {
        var key = self.next(&i).?;
        var value: ?[]const u8 = null;

        if (mem.indexOf(u8, key, "=")) |pos| {
            value = key[(pos + 1)..];
            key = key[0..pos];
        }

        if (mem.startsWith(u8, key, "--")) {
            if (mem.eql(u8, key, "--")) {
                while (self.next(&i)) |pos|
                    try self.positionals.append(self.allocator, pos);
                return;
            }

            const key_name = key[2..];
            const desc = self.getDescFromLong(key_name);

            const val = try self.makeValue(key_name, value, &i, desc);
            try self.arguments.put(self.allocator, key_name, val);
        } else if (mem.startsWith(u8, key, "-")) {
            for (key[1..]) |k, id| {
                if (k == '=') break;

                const key_name = key[id + 1 .. id + 2];
                const desc = self.getDescFromShort(key_name);

                if (key[id + 1] == '=' or id + 2 == key.len) {
                    const val = try self.makeValue(key_name, value, &i, desc);
                    try self.arguments.put(self.allocator, desc.long, val);
                } else {
                    if (desc.need_value) {
                        std.debug.print("expected value for key '{s}'\n", .{key_name});
                    } else {
                        try self.arguments.put(self.allocator, desc.long, "true");
                    }
                }
            }
        } else {
            try self.positionals.append(self.allocator, key);
        }
    }
}
