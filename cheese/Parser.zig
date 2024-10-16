﻿const std = @import("std");

/// modoule, flag, or variable
///
/// `zig init` where `init` is a Module
/// `zig fetch --save` where `--save` is a LongFlag
/// `gcc main.c -o main` where `-o` is a Flag (might be any length)
/// `zig build -Doptimize=Debug` where `Doptimize` is Variable,
/// `Debug` is its Value
///
/// since 0.1.0
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

/// each `Option` has value (see ArgType.Option)
/// `zig fetch --save https://whatever.com` where
/// save = https://whatever.com
/// may also be asigned with `=`
///
/// if mutiple values given, then Multiple is active:
/// `program -nums 1 2 3 4`
///
/// since 0.1.0
pub const ValueType = union(enum) {
    const Self = @This();

    Single: []const u8,
    Multiple: std.ArrayList([]const u8),

    pub fn init(value: []const u8) Self {
        return Self{
            .Single = value,
        };
    }

    pub fn add(self: *Self, value: []const u8, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
        switch (self.*) {
            .Single => {
                var list = std.ArrayList([]const u8).init(allocator);
                try list.append(self.Single);
                try list.append(value);
                self.* = Self{ .Multiple = list };
            },
            .Multiple => try self.Multiple.append(value),
        }
    }

    pub fn deinit(self: Self) void {
        if (self == .Single) return;
        self.Multiple.deinit();
    }
};

/// ArgType.Option has Variable() as its type
/// `$ zig-out/bin/play --num=5 --or_even 1 false i-love-zig 2.3`
/// `num : 5`
/// `or_even :`
/// `   1`
/// `   false`
/// `   i-love-zig`
/// `   2.3`
///
/// since 0.1.0
pub fn Variable() type {
    return struct {
        const Self = @This();

        name: []const u8,
        value: ValueType,
        allocator: std.mem.Allocator,

        pub fn init(name: []const u8, value: []const u8, allocator: std.mem.Allocator) Self {
            return Self{
                .name = name,
                .value = ValueType.init(value),
                .allocator = allocator,
            };
        }

        pub fn add(self: *Self, value: []const u8) std.mem.Allocator.Error!void {
            try self.value.add(value, self.allocator);
        }

        pub fn andAndGetSelf(self: Self, value: []const u8) std.mem.Allocator.Error!Self {
            try self.value.add(value, self.allocator);
            return self;
        }

        pub fn int(self: Self, comptime IntType: type) std.fmt.ParseIntError!IntType {
            return std.fmt.parseInt(IntType, self.value.Single, 10);
        }

        pub fn nums(self: Self, comptime NumType: type) std.fmt.ParseIntError![]NumType {
            var output: NumType = [_]NumType{0} ** self.value.Multiple.items.len;

            for (self.value.Multiple.items, 0..) |string, i|
                output[i] = try std.fmt.parseInt(NumType, string, 10);
            return output;
        }

        pub fn float(self: Self, comptime FloatType: type) std.fmt.ParseIntError!FloatType {
            return std.fmt.parseFloat(FloatType, self.value.Single);
        }
    };
}

/// for hashing args into std.HashMap
const HashType = u8;

/// each cmd argument fiven translates into Arg()
/// one datatype with multiple implimentations (see ArgType()
/// which is stored as `value` field)
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

        pub fn Option(variable: []const u8, value: []const u8, allocator: std.mem.Allocator) Self {
            return Self{ .value = .{ .Option = Variable().init(variable, value, allocator) } };
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

/// only for argument name hashing
pub fn hash(value: []const u8) HashType {
    const a: u10 = value[0];
    const b: u10 = if (value.len > 1) value[1] else 0;
    const c: u10 = if (value.len > 1) value[value.len - 1] else 1;

    return @intCast((a + b + c) % 256);
}

/// stores arguments
///
/// check arg existance with `declared` field
/// it stores no order, and shows
/// no repeats (but only the last repeated instance)
/// trying to extract user input: O(1)
///
/// check user input word by word with `repeated` field
/// it stores everything given to program, with
/// given order
/// trying to extract user input: O(N)
///
/// since 0.1.0
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
            for (self.repeated.items) |arg| {
                if (arg.value != .Option) continue;
                arg.value.Option.value.deinit();
            }

            self.repeated.deinit();
            self.declared.deinit();
        }
    };
}

/// return user input using 2 forms (see ParseOutput())
///
/// play it out:
/// ```
/// zig build play
/// ./zig-out/bin/play your_input
/// ```
///
/// since 0.1.0
pub fn ParseArgs(allocator: std.mem.Allocator) ParseError!ParseOutput() {
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

                var new = switch (old.value) {
                    .Flag => |value| Arg().Option(value, arg, allocator),
                    .LongFlag => |value| Arg().Option(value, arg, allocator),
                    .Option => old,
                    else => unreachable,
                };

                if (old.value == .Option) new.value.Option.add(arg) catch unreachable;

                output.swap(output.repeated.items.len - 1, last_added_key, new) catch return ParseError.OutOfMemory;
            }
            continue;
        }

        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-') { //           long flags or options (variables)
            const eql_index = std.mem.indexOf(u8, arg, "=");
            if (eql_index) |index| { //             option (variable)
                last_added_key = output.addAndGetHash(Arg().Option(arg[2..index], arg[index + 1 ..], allocator)) catch return ParseError.OutOfMemory;
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

/// DO NOT USE
pub fn splitFlagChainNonRepeat(comptime single_char_flags: []const u8, arg: []const u8, allocator: std.mem.Allocator) std.ArrayList(u8) {
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
