const std = @import("std");
const t = @import("types.zig");

pub const ParseError = error{
    NoValueHolder,
    OutOfMemory,
    RepeatsNotAllowed,
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

        pub fn add(self: *Self, arg: t.Arg()) ParseError!void {
            self.declared.put(arg.asString(), arg) catch return ParseError.OutOfMemory;
            self.repeated.append(arg) catch return ParseError.OutOfMemory;
        }

        pub fn swap(self: *Self, index: usize, old_name: []const u8, new: t.Arg()) ParseError!void {
            _ = self.repeated.swapRemove(index);
            self.repeated.insert(index, new) catch return ParseError.OutOfMemory;

            self.declared.put(old_name, new) catch return ParseError.OutOfMemory;
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
    allow_flag_repeats: bool = true,
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
    errdefer output.deinit();
    var last_added_key: []const u8 = undefined;

    while (args_iter.next()) |arg| {
        if (arg[0] != '-') { //             module or variables value
            if (at_module_section) { //             module
                const new_arg = t.Arg().Module(arg);
                try output.add(t.Arg().Module(arg));
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

                if (old.value == .Option) new.value.Option.add(arg) catch return ParseError.OutOfMemory;

                try output.swap(output.repeated.items.len - 1, last_added_key, new);
            }
            continue;
        }

        if (arg[0] == '-' and arg.len > 1) {
            const eql_index_null = std.mem.indexOf(u8, arg, "=");
            const name_start: usize = if (arg[1] == '-') 2 else 1;
            var name: []const u8 = undefined;

            if (eql_index_null) |eql_index| { //                   option
                name = arg[name_start..eql_index];
                try output.add(t.Arg().Option(name, arg[eql_index + 1 ..], allocator));
            } else { //                                            Flag/LongFlag
                name = arg[name_start..];
                switch (name_start) {
                    1 => {
                        if (name.len > 1) {
                            var is_chainable_flag = false;

                            if (opts.chainable_flags.len > 0) {
                                var unchained_null = try Unchain(opts.chainable_flags, name, true, allocator);
                                if (unchained_null) |unchained| {
                                    defer unchained_null.?.deinit();
                                    is_chainable_flag = true;
                                    for (unchained.repeated.items) |flag| {
                                        if (output.declared.get(flag.asString())) |_| {
                                            if (opts.allow_flag_repeats) {
                                                try output.add(flag); // TODO: tf is going on
                                            } else return ParseError.RepeatsNotAllowed;
                                        } else try output.add(flag);
                                    }
                                } else if (!opts.allow_long_singledash_flags) return ParseError.WrongChain;
                            }

                            if (!is_chainable_flag and opts.allow_long_singledash_flags)
                                try output.add(t.Arg().Flag(name));
                        } else try output.add(t.Arg().Flag(name));
                    },
                    2 => {
                        try output.add(t.Arg().LongFlag(name));
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
            if (output.declared.get(arg[i .. i + 1]) != null and !allow_repeats) return ParseError.RepeatsNotAllowed;
            output.add(t.Arg().Flag(arg[i .. i + 1])) catch return ParseError.OutOfMemory;
        } else {
            output.deinit();
            return null;
        }
    }

    return output;
}
