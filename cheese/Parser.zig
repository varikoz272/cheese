const std = @import("std");
const t = @import("types.zig");

pub const ParseError = error{
    NoValueHolder,
    OutOfMemory,
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

            // _ = self.declared.remove(old_name);
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

/// return user input using 2 forms (see ParseOutput())
//
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
            var new_arg: t.Arg() = undefined;

            if (eql_index_null) |eql_index| { //                   option
                new_arg = t.Arg().Option(arg[name_start..eql_index], arg[eql_index + 1 ..], allocator);
                name = new_arg.asString();
            } else { //                                            Flag/LongFlag
                name = arg[name_start..];
                new_arg = switch (name_start) {
                    1 => t.Arg().Flag(name),
                    2 => t.Arg().LongFlag(name),
                    else => unreachable,
                };
            }

            output.add(new_arg) catch return ParseError.OutOfMemory;
            last_added_key = name;
            at_module_section = false;
            continue;
        }

        @panic("Invalid argument");
    }

    return output;
}
