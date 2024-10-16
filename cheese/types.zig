const std = @import("std");

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
