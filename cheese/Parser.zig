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
    OutOfMemory,
};

pub fn hash(value: []const u8) HashType {
    const a: u10 = value[0];
    const b: u10 = if (value.len > 1) value[1] else 0;
    const c: u10 = if (value.len > 1) value[value.len - 1] else 1;

    return @intCast((a + b + c) % 256);
}

pub fn ParseOutput() type {
    return struct {
        const Self = @This();

        repeated: std.ArrayList(Arg()),
        declared: std.AutoHashMap(HashType, Arg()),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .repeated = std.ArrayList(Arg()).init(allocator),
                .declared = std.AutoHashMap(HashType, Arg()).init(allocator),
            };
        }

        pub fn addAndGetHash(self: *Self, arg: Arg()) std.mem.Allocator.Error!HashType {
            try self.repeated.append(arg);

            const arg_hash = hash(arg.asString());
            try self.declared.put(arg_hash, arg);
            return arg_hash;
        }

        pub fn swap(self: *Self, index: usize, old_hash: HashType, new: Arg()) std.mem.Allocator.Error!void {
            _ = self.repeated.swapRemove(index);
            try self.repeated.insert(index, new);

            _ = self.declared.remove(old_hash);
            try self.declared.put(old_hash, new);
        }

        pub fn deinit(self: *Self) void {
            self.repeated.deinit();
            self.declared.deinit();
        }
    };
}

pub fn parseArgs(allocator: std.mem.Allocator) ParseError!ParseOutput() {
    var args_iter = std.process.argsWithAllocator(allocator) catch return ParseError.OutOfMemory;
    defer args_iter.deinit();

    _ = args_iter.next(); // skip executable

    var at_module_section = true; // modules used to before flags. if not then error

    var output = ParseOutput().init(allocator);
    var last_added_key: HashType = 0;

    while (args_iter.next()) |arg| {
        if (arg[0] != '-') { //             module or variables value
            if (at_module_section) { //             module
                last_added_key = output.addAndGetHash(Arg().Module(arg)) catch return ParseError.OutOfMemory;
            } else { //             variables value
                if (output.repeated.items.len == 0) return ParseError.NoValueHolder;

                const old = output.repeated.getLast();

                const new = switch (old.value) {
                    .Flag => |value| Arg().Option(value, arg),
                    .LongFlag => |value| Arg().Option(value, arg),
                    .Option => |value| Arg().Option(value.name, arg),
                    else => unreachable,
                };

                output.swap(output.repeated.items.len - 1, last_added_key, new) catch return ParseError.OutOfMemory;
            }
            continue;
        }

        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-') { //           long flags or options (variables)
            const eql_index = std.mem.indexOf(u8, arg, "=");
            if (eql_index) |index| { //             option (variable)
                last_added_key = output.addAndGetHash(Arg().Option(arg[2..index], arg[index + 1 ..])) catch return ParseError.OutOfMemory;
            } else { //             long flag
                last_added_key = output.addAndGetHash(Arg().LongFlag(arg[2..])) catch return ParseError.OutOfMemory;
            }

            at_module_section = false;
            continue;
        }

        if (arg[0] == '-') { // short flag
            last_added_key = output.addAndGetHash(Arg().Flag(arg[1..])) catch return ParseError.OutOfMemory;

            at_module_section = false;
            continue;
        }

        @panic("Invalid argument");
    }

    return output;
}

/// const cmd_arg = rffr;
/// const flag_list = splitFlagComboNonRepeat("rf", cmd_arg); // returns {'r', 'f'}
pub fn splitFlagComboNonRepeat(comptime single_char_flags: []const u8, arg: []const u8, allocator: std.mem.Allocator) std.ArrayList(u8) {
    var arg_copy = std.AutoHashMap(u8, u8).init(allocator);
    defer arg_copy.deinit();

    for (arg) |char| {
        arg_copy.put(char, char) catch unreachable;
    }

    var splited = std.ArrayList(u8).init(allocator);
    for (single_char_flags) |char| {
        if (arg_copy.get(char)) |flag| {
            splited.append(flag) catch unreachable;
            _ = arg_copy.remove(char);
        }
    }

    return splited;
}
