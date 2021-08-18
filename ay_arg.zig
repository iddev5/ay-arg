// This file is licensed under MIT No Attribution License.  
// See LICENSE for more info.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Arg = struct {
    key: ?[]const u8,
    value: ?[]const u8,
};

pub const ArgList = std.StringHashMap([]const u8);

pub const ArgParse = struct {
    args: [][]u8,

    const Self = @This();

    pub fn init(args: [][]u8) Self {
        return .{
            .args = args,
        };
    }

    pub fn free(self: *Self) void {
        _ = self;
    }

    fn forward(self: *Self, index: *usize) ?[]const u8 {
        if (index.* < self.args.len) {
            index.* += 1;
            return self.args[index.* - 1];
        }

        return null;
    }

    fn backward(self: *Self, index: *usize) void {
        _ = self;
        index.* -= 1;
    }

    fn isValidKey(self: *Self, key: []const u8) bool {
        _ = self;
        if (key[0] == '-' and !std.mem.eql(u8, key, "-")) {
            for (key) |c| {
                if (!(std.ascii.isAlNum(c) or c == '_' or c == '-' or c == '=' or c >= 0x80)) {
                    return false;
                }
            }
        } else {
            return false;
        }

        return true;
    }

    pub fn parse(self: *Self, allocator: *Allocator) !ArgList {
        var map = ArgList.init(allocator);
        errdefer map.deinit();

        var index: usize = 0;

        while (index < self.args.len) {
            var key = self.forward(&index).?;
            var value: ?[]const u8 = self.forward(&index) orelse "true";

            if (self.isValidKey(key)) {
                // If key has a 'equal' character inside it then first
                // find its position
                // i.e. -key=value
                const eqpos = std.mem.indexOf(u8, key, "=");
                if (eqpos != null) {
                    if (eqpos.? == key.len - 1)
                        return error.IncompleteArgPair;

                    // If not end of arguments, then go backward
                    if (!std.mem.eql(u8, value.?, "true"))
                        self.backward(&index);

                    const temp = key;

                    // Get the key slice, which is key start to equal position
                    // Value is from equal position + 1 (for the equal character itself) to end
                    key = key[0..eqpos.?];
                    value = temp[eqpos.? + 1 ..];
                }
                // Value exists for key in its own independent position
                // i.e -key value
                else {
                    // The arg is a flag
                    if (value.?[0] == '-') {
                        value = "true";
                        self.backward(&index);
                    }
                }

                try map.put(key[1..], value.?);
            } else {
                return error.InvalidArgumentKey;
            }
        }

        return map;
    }
};
