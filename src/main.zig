const std = @import("std");
const Parser = @import("Parser.zig");

pub fn main() void {
    testSplit();
}

pub fn testSplit() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const flags = Parser.splitFlagComboNonRepeat("rf", "rffr", gpa.allocator());
    defer flags.deinit();
    for (flags.items) |item| {
        std.debug.print("{c}\n", .{item});
    }
}

pub fn testParsing() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = Parser.parseArgs(gpa.allocator()) catch {
        std.debug.print("no variable holder", .{});
        return;
    };
    defer args.deinit();

    var iter = args.iterator();
    while (iter.next()) |entry| {
        const item = entry.value_ptr.*;
        if (item.value == .Option) {
            std.debug.print("{s} : {} ({s})\n", .{ item.value.Option.name, item.value.Option.int(i32) catch -1, item.value.typeAsString() });
        } else {
            std.debug.print("{s} ({s})\n", .{ item.asString(), item.value.typeAsString() });
        }
    }
}
