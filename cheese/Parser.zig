const std = @import("std");
const t = @import("types.zig");

pub const ParseError = error{
    NoValueHolder,
    OutOfMemory,
    RepeatedButNotAllowed,
    WrongChain,
};

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

        repeated: std.ArrayList(t.Arg()),
        declared: std.StringHashMap(t.Arg()),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .repeated = std.ArrayList(t.Arg()).init(allocator),
                .declared = std.StringHashMap(t.Arg()).init(allocator),
            };
        }

        pub fn add(self: *Self, arg: t.Arg()) std.mem.Allocator.Error!void {
            try self.repeated.append(arg);

            try self.declared.put(arg.asString(), arg);
        }

        pub fn swap(self: *Self, index: usize, old_name: []const u8, new: t.Arg()) std.mem.Allocator.Error!void {
            _ = self.repeated.swapRemove(index);
            try self.repeated.insert(index, new);

            try self.declared.put(old_name, new);
        }

        pub fn deinit(self: *Self) void {
            for (self.repeated.items) |arg| {
                if (arg.value == .Option)
                    arg.value.Option.value.deinit();
            }

            self.repeated.deinit();
            self.declared.deinit();
        }
    };
}

pub const ParseOptions = struct {
    chainable_flags: []const u8 = "",
    allow_long_singledash_flags: bool = true,
    allow_repeats: bool = true,
};

/// return user input using 2 forms (see ParseOutput())
//
/// play it out:
/// ```
/// zig build play
/// ./zig-out/bin/play your_input
/// ```
///
/// since 0.1.0
pub fn ParseArgs(comptime opts: ParseOptions, allocator: std.mem.Allocator) ParseError!ParseOutput() {
    var args_iter = std.process.argsWithAllocator(allocator) catch return ParseError.OutOfMemory;
    defer args_iter.deinit();

    _ = args_iter.next(); // skip executable

    var at_module_section = true; // modules used to before flags. if not then error

    var output = ParseOutput().init(allocator);
    var last_added_key: []const u8 = undefined;

    while (args_iter.next()) |arg| {
        if (arg[0] != '-') { //             module or variables value
            if (at_module_section) { //             module
                const new_arg = t.Arg().Module(arg);
                output.add(t.Arg().Module(arg)) catch return ParseError.OutOfMemory;
                last_added_key = new_arg.asString();
            } else { //             variables value
                if (output.repeated.items.len == 0) return ParseError.NoValueHolder;

                const old = output.repeated.getLast();

                var new = switch (old.value) {
                    .Flag => |value| t.Arg().Option(value, arg, allocator),
                    .LongFlag => |value| t.Arg().Option(value, arg, allocator),
                    .Option => old,
                    else => unreachable,
                };

                if (old.value == .Option) new.value.Option.add(arg) catch unreachable;

                output.swap(output.repeated.items.len - 1, last_added_key, new) catch return ParseError.OutOfMemory;
            }
            continue;
        }

        if (arg[0] == '-' and arg.len > 1) {
            const eql_index_null = std.mem.indexOf(u8, arg, "=");
            const name_start: usize = if (arg[1] == '-') 2 else 1;
            var name: []const u8 = undefined;

            if (eql_index_null) |eql_index| { //                   option
                name = arg[name_start..eql_index];
                output.add(t.Arg().Option(name, arg[eql_index + 1 ..], allocator)) catch return ParseError.OutOfMemory;
            } else { //                                            Flag/LongFlag
                name = arg[name_start..];
                switch (name_start) {
                    1 => {
                        if (name.len > 1) {
                            var is_chainable_flag = false;

                            if (opts.chainable_flags.len > 0) {
                                var unchained_null = try Unchain(opts.chainable_flags, name, true, allocator);
                                if (unchained_null) |unchained| {
                                    is_chainable_flag = true;
                                    for (unchained.repeated.items) |flag| output.add(flag) catch return ParseError.OutOfMemory;
                                    unchained_null.?.deinit();
                                } else if (!opts.allow_long_singledash_flags) return ParseError.WrongChain;
                            }

                            if (!is_chainable_flag and opts.allow_long_singledash_flags)
                                output.add(t.Arg().Flag(name)) catch return ParseError.OutOfMemory;
                        } else output.add(t.Arg().Flag(name)) catch return ParseError.OutOfMemory;
                    },
                    2 => {
                        output.add(t.Arg().LongFlag(name)) catch return ParseError.OutOfMemory;
                    },
                    else => unreachable,
                }
            }

            last_added_key = name;
            at_module_section = false;
            continue;
        }

        @panic("Invalid argument");
    }

    return output;
}

/// returns null if either arg has not only
/// chainable_flags symbols or if flag is
/// repeated but not allowed
fn Unchain(comptime chainable_flags: []const u8, arg: []const u8, allow_repeats: bool, allocator: std.mem.Allocator) ParseError!?ParseOutput() {
    var hash_mapped_flags = [_]?u0{null} ** 256;
    for (chainable_flags) |flag|
        hash_mapped_flags[flag] = 0;

    var output = ParseOutput().init(allocator);

    for (arg, 0..) |possible_flag, i| {
        if (hash_mapped_flags[possible_flag]) |_| {
            if (output.declared.get(arg[i .. i + 1]) != null and !allow_repeats) return ParseError.RepeatedButNotAllowed;
            output.add(t.Arg().Flag(arg[i .. i + 1])) catch return ParseError.OutOfMemory;
        } else {
            output.deinit();
            return null;
        }
    }

    return output;
}
