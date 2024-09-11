const std = @import("std");
const Simulator = @import("testing/simulation/simulator.zig").Simulator;
const log = std.log.scoped(.main);

pub const std_options = struct {
    pub const log_level: std.log.Level = .debug;
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const simulator = Simulator.init(allocator, null) catch |err| {
        log.err("Error initializing simulator", .{});
        return err;
    };
    errdefer simulator.deinit();

    simulator.run() catch |err| {
        log.err("Error running simulator", .{});
        return err;
    };
    simulator.deinit();
}
