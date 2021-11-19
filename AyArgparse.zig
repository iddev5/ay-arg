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

fn getDescFromLong(self: *AyArgparse, long: []const u8) !ParamDesc {
    for (self.params) |param| {
        if (mem.eql(u8, param.long, long)) {
            return param;
        }
    }

    std.debug.print("invalid argument '--{s}'\n", .{long});
    return error.ArgparseError;
}

fn getDescFromShort(self: *AyArgparse, short: []const u8) !ParamDesc {
    for (self.params) |param| if (param.short) |p_short| {
        if (mem.eql(u8, p_short, short)) {
            return param;
        }
    };

    std.debug.print("invalid argument '-{s}'\n", .{short});
    return error.ArgparseError;
}

inline fn makeValue(self: *AyArgparse, key: []const u8, value: ?[]const u8, i: *usize, desc: ParamDesc) ![]const u8 {
    return blk: {
        if (desc.need_value) {
            break :blk value orelse self.next(i) orelse {
                std.debug.print("expected value for key '{s}'\n", .{key});
                return error.ArgparseError;
            };
        } else if (value != null) {
            std.debug.print("key '{s}' does not take value\n", .{key});
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

                const val_final = try self.makeValue(key, val, &i, desc);
                try self.arguments.put(self.allocator, key_name, val_final);

                if (has_value) break;
            }
        } else {
            try self.positionals.append(self.allocator, key);
        }
    }
}
