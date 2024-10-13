const std = @import("std");
pub const ArgType = union(enum) {
    const Self = @This();

    Flag: []const u8,
    LongFlag: []const u8,
    Option: Variable(),
    Module: []const u8,

    pub fn typeAsString(self: Self) []const u8 {
        switch (self) {
            .Flag => return "Flag",
            .LongFlag => return "LongFlag",
            .Option => return "Option",
            .Module => return "Module",
        }
    }
};

pub fn Variable() type {
    return struct {
        const Self = @This();

        name: []const u8,
        value: []const u8,

        pub fn init(name: []const u8, value: []const u8) Self {
            return Self{
                .name = name,
                .value = value,
            };
        }

        pub fn int(self: Self, comptime IntType: type) std.fmt.ParseIntError!IntType {
            return std.fmt.parseInt(IntType, self.value, 10);
        }

        pub fn float(self: Self, comptime FloatType: type) std.fmt.ParseIntError!FloatType {
            return std.fmt.parseFloat(FloatType, self.value);
        }
    };
}

const HashType = u8;

pub fn Arg() type {
    return struct {
        const Self = @This();

        value: ArgType,

        pub fn Flag(char: []const u8) Self {
            return Self{ .value = .{ .Flag = char } };
        }

        pub fn Module(name: []const u8) Self {
            return Self{ .value = .{ .Module = name } };
        }

        pub fn LongFlag(name: []const u8) Self {
            return Self{ .value = .{ .LongFlag = name } };
        }

        pub fn Option(variable: []const u8, value: []const u8) Self {
            return Self{ .value = .{ .Option = Variable().init(variable, value) } };
        }

        pub fn asString(self: Self) []const u8 {
            switch (self.value) {
                .Flag => |value| return value,
                .LongFlag => |value| return value,
                .Option => |value| return value.name,
                .Module => |value| return value,
            }
        }
    };
}

pub const ParseError = error{
    NoValueHolder,
};

pub fn hash(value: []const u8) HashType {
    const a: u10 = value[0];
    const b: u10 = if (value.len > 1) value[1] else 0;
    const c: u10 = if (value.len > 1) value[value.len - 1] else 1;

    return @intCast((a + b + c) % 256);
}

pub fn parseArgs(allocator: std.mem.Allocator) ParseError!std.AutoHashMap(HashType, Arg()) {
    var args_iter = std.process.argsWithAllocator(allocator) catch unreachable;
    defer args_iter.deinit();

    _ = args_iter.next(); // skip executable

    var at_module_section = true; // modules used to before flags. if not then error

    var args_list = std.AutoHashMap(HashType, Arg()).init(allocator);
    var last_added_key: HashType = 0;

    while (args_iter.next()) |arg| {
        if (arg[0] != '-') { //             module or variables value
            if (at_module_section) { //             module
                const arg_hash = hash(arg);
                args_list.put(arg_hash, Arg().Module(arg)) catch unreachable;
                last_added_key = arg_hash;
            } else { //             variables value
                if (args_list.count() == 0) return ParseError.NoValueHolder;

                const old_null = args_list.get(last_added_key);

                if (old_null) |old| {
                    const new = switch (old.value) {
                        .Flag => |value| Arg().Option(value, arg),
                        .LongFlag => |value| Arg().Option(value, arg),
                        .Option => |value| Arg().Option(value.name, arg),
                        else => unreachable,
                    };

                    _ = args_list.remove(last_added_key);
                    args_list.put(last_added_key, new) catch unreachable;
                } else {
                    var iter = args_list.iterator();
                    while (iter.next()) |entry| {
                        std.debug.print("key: {}, value: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.*.asString() });
                    }
                }
            }
            continue;
        }

        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-') { //           long flags or options (variables)
            const eql_index = std.mem.indexOf(u8, arg, "=");
            const arg_hash = hash(arg[2..]);
            if (eql_index) |index| { //             option (variable)
                args_list.put(arg_hash, Arg().Option(arg[2..index], arg[index + 1 ..])) catch unreachable;
                last_added_key = arg_hash;
            } else { //             long flag
                args_list.put(arg_hash, Arg().LongFlag(arg[2..])) catch unreachable;
                last_added_key = arg_hash;
            }

            at_module_section = false;
            continue;
        }

        if (arg[0] == '-') { // short flag
            const arg_hash = hash(arg[1..]);
            args_list.put(arg_hash, Arg().Flag(arg[1..])) catch unreachable;
            last_added_key = arg_hash;

            at_module_section = false;
            continue;
        }

        @panic("Invalid argument");
    }

    return args_list;
}
