const std = @import("std");
const Parser = @import("Parser.zig");

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const chainable = "ab";

    var args = Parser.ParseArgs(.{ .chainable_flags = chainable }, gpa.allocator()) catch {
        std.debug.print("ERROR", .{});
        return;
    };
    defer args.deinit();

    for (args.repeated.items) |item| {
        const arg_type = item.value.typeAsString();

        if (item.value == .Option) {
            if (item.value.Option.value == .Single) {
                std.debug.print("{s} : {} ({s})\n", .{ item.value.Option.name, item.value.Option.int(i32) catch 0, arg_type });
            } else {
                std.debug.print("{s} : ({s})\n", .{ item.value.Option.name, arg_type });
                for (item.value.Option.value.Multiple.items) |int|
                    std.debug.print("    {s}\n", .{int});
            }
        } else {
            std.debug.print("{s} ({s})\n", .{ item.asString(), arg_type });
        }
    }
}
