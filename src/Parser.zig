const std = @import("std");

pub const ArgType = union(enum) {
    Flag: []const u8,
    LongFlag: []const u8,
    Option: Variable(),
    Module: []const u8,
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
    };
}

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

        pub fn toString(self: Self) []const u8 {
            switch (self.value) {
                .Flag => |value| return value,
                .LongFlag => |value| return value,
                .Option => |value| return value.name,
                .Module => |value| return value,
            }
        }

        pub fn hash(value: []const u8) u8 {
            return value[0] *% if (value.len > 1) value[1] else 0;
        }
    };
}

pub const ParseError = error{
    NoValueHolder,
};

pub fn parseArgs(allocator: std.mem.Allocator) ParseError!std.ArrayList(Arg()) {
    var args_iter = std.process.argsWithAllocator(allocator) catch unreachable;
    defer args_iter.deinit();

    _ = args_iter.next(); // skip executable

    var at_module_section = true; // modules used to before flags. if not then error

    var args_list = std.ArrayList(Arg()).init(allocator);

    while (args_iter.next()) |arg| {
        if (arg.len == 2 and arg[0] == '-') {
            args_list.append(Arg().Flag(arg[1..])) catch unreachable;
            at_module_section = false;
        }

        if (arg[0] != '-') {
            if (at_module_section) {
                args_list.append(Arg().Module(arg)) catch unreachable;
            } else {
                if (args_list.items.len == 0) return ParseError.NoValueHolder;

                const old = args_list.swapRemove(args_list.items.len - 1);
                const new = switch (old.value) {
                    .Flag => |value| Arg().Option(value, arg),
                    .LongFlag => |value| Arg().Option(value, arg),
                    .Option => |value| Arg().Option(value.name, arg),
                    else => unreachable,
                };

                args_list.append(new) catch unreachable;
            }
        }

        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-') {
            const eql_index = std.mem.indexOf(u8, arg, "=");

            if (eql_index) |index| {
                args_list.append(Arg().Option(arg[2..index], arg[index + 1 ..])) catch unreachable;
            } else {
                args_list.append(Arg().LongFlag(arg[2..])) catch unreachable;
            }

            at_module_section = false;
        }
    }

    return args_list;
}
