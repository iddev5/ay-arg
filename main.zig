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

pub const Error = error{
    UnknownArgument,
    ExpectedValue,
    UnexpectedValue,
};

pub const ParamDesc = struct {
    long: []const u8,
    short: ?[]const u8 = null,
    need_value: bool = false,
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
        if (mem.eql(u8, p_short, short)) {
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

                const val_final = try self.makeValue(key, val, &i, desc);
                try self.arguments.put(self.allocator, key_name, val_final);

                if (has_value) break;
            }
        } else {
            try self.positionals.append(self.allocator, key);
        }
    }
}
