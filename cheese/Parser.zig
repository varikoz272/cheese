const std = @import("std");
const t = @import("types.zig");

pub const ParseError = error{
    NoValueHolder,
    OutOfMemory,
    RepeatsNotAllowed,
    WrongChain,
    WrongArgLength,
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
    allow_inchain_repeats: bool = true,
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
            var parsed = try ParseFlagOrLongOrOption(opts, arg, allocator);
            defer parsed.deinit();
            for (parsed.repeated.items) |flag_long_option| try output.add(flag_long_option);

            last_added_key = parsed.repeated.items[parsed.repeated.items.len - 1].asString();
            at_module_section = false;
            continue;
        }

        unreachable;
    }

    return output;
}

pub fn ParseFlagOrLongOrOption(comptime opts: ParseOptions, full_arg: []const u8, allocator: std.mem.Allocator) ParseError!ParseOutput() {
    if (full_arg.len < 2) return ParseError.WrongArgLength;

    if (full_arg[1] != '-') return ParseFlagOrChain(opts, full_arg[1..], allocator); // single -

    var output = ParseOutput().init(allocator);
    errdefer output.deinit();

    const eql_index_null = std.mem.indexOf(u8, full_arg[2..], "=");

    if (eql_index_null) |eql_index| {
        try output.add(t.Arg().Option(full_arg[2..], full_arg[eql_index + 1 ..], allocator));
    } else try output.add(t.Arg().LongFlag(full_arg[2..]));

    return output;
}

pub fn ParseFlagOrChain(comptime opts: ParseOptions, name: []const u8, allocator: std.mem.Allocator) ParseError!ParseOutput() {
    var output = ParseOutput().init(allocator);
    errdefer output.deinit();

    if (name.len == 0) return ParseError.WrongArgLength;

    if (name.len == 1) {
        try output.add(t.Arg().Flag(name));
        return output; // just a flag
    }

    if (opts.chainable_flags.len > 0) {
        var unchained_null = try Unchain(opts.chainable_flags, name, opts.allow_inchain_repeats, allocator);

        if (unchained_null) |unchained| {
            defer unchained_null.?.deinit();
            for (unchained.repeated.items) |flag| try output.add(flag);
            return output; // chained flags
        }

        if (opts.allow_long_singledash_flags) {
            try output.add(t.Arg().Flag(name));
            return output; // long flag with -
        }
        return ParseError.WrongArgLength;
    }

    if (opts.allow_long_singledash_flags) {
        try output.add(t.Arg().Flag(name));
        return output; // long flag with -
    }

    unreachable;
}

/// returns null if either arg has not only
/// chainable_flags symbols or if flag is
/// repeated but not allowed
fn Unchain(comptime chainable_flags: []const u8, arg: []const u8, allow_repeats: bool, allocator: std.mem.Allocator) ParseError!?ParseOutput() {
    var hash_mapped_flags = [_]?u0{null} ** 256;
    for (chainable_flags) |flag|
        hash_mapped_flags[flag] = 0;

    var output = ParseOutput().init(allocator);
    errdefer output.deinit();

    for (arg, 0..) |possible_flag, i| {
        if (hash_mapped_flags[possible_flag]) |_| {
            if (output.declared.get(arg[i .. i + 1]) != null and !allow_repeats) return ParseError.RepeatsNotAllowed;
            try output.add(t.Arg().Flag(arg[i .. i + 1]));
        } else {
            output.deinit();
            return null;
        }
    }

    return output;
}
