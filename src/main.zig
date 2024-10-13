const std = @import("std");
const Parser = @import("Parser.zig");

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const args = Parser.parseArgs(gpa.allocator()) catch {
        std.debug.print("no variable holder", .{});
        return;
    };
    defer args.deinit();

    for (args.items) |item| {
        if (item.value == .Option) {
            std.debug.print("{s} : {} ({s})\n", .{ item.value.Option.name, item.value.Option.int(i32) catch -1, item.value.typeAsString() });
        } else {
            std.debug.print("{s} ({s})\n", .{ item.asString(), item.value.typeAsString() });
        }
    }
}
