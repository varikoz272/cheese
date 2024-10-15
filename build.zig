const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const play_step = b.step("play", "returns any cmd input parsed (test)");
    const play = b.addExecutable(.{
        .name = "play",
        .root_source_file = b.path("cheese/ping.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_play = b.addRunArtifact(play);
    b.installArtifact(play);
    play_step.dependOn(&run_play.step);

    if (b.args) |args| run_play.addArgs(args);

    const module = b.addModule("cheese", .{ .root_source_file = b.path("cheese/Parser.zig") });
    _ = module;
}
