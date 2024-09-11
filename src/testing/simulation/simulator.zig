const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.simulator);

const ClusterType = @import("cluster.zig").ClusterType;
const Network = @import("network.zig").Network;
const Scheduler = @import("scheduler.zig").Scheduler;
const StateMachineType = @import("../state_machine.zig").StateMachineType;
const Cluster = ClusterType(StateMachineType);

pub const Simulator = struct {
    const Self = @This();
    pub const Options = struct {
        cluster: Cluster.Options,
        network: Network.Options,
        scheduler: Scheduler.Options,
        iterations: u64,
        ticks_per_iteration: u64,
        cluster_ticks_per_network_tick: u64,
    };

    options: Options,
    allocator: mem.Allocator,
    scheduler: *Scheduler,
    network: *Network,

    pub fn default_options() Options {
        return Options{
            .cluster = Cluster.default_options(),
            .network = Network.default_options(),
            .scheduler = Scheduler.default_options(),
            .iterations = 10,
            .ticks_per_iteration = 100,
            .cluster_ticks_per_network_tick = 3,
        };
    }

    pub fn init(allocator: mem.Allocator, options_o: ?Options) !*Simulator {
        var options = default_options();
        if (options_o) |o| {
            options = o;
        }
        var scheduler = try Scheduler.init(allocator, options.scheduler);
        errdefer scheduler.deinit();

        var network = try Network.init(allocator, options.network, scheduler);
        errdefer network.deinit();

        log.info("Creating simulator", .{});
        var simulator = try allocator.create(Simulator);
        errdefer allocator.destroy(simulator);

        simulator.* = Self{
            .options = options,
            .allocator = allocator,
            .scheduler = scheduler,
            .network = network,
        };

        return simulator;
    }

    pub fn deinit(self: *Simulator) void {
        self.scheduler.deinit();
        self.network.deinit();
        self.allocator.destroy(self);
    }

    pub fn run(self: *Self) !void {
        var iterations = self.options.iterations;
        log.info("Running simulator for {d} iterations", .{iterations});
        var ticks_per_iteration = self.options.ticks_per_iteration;
        var cluster_ticks_per_network_tick = self.options.cluster_ticks_per_network_tick;

        for (0..iterations) |iter| {
            log.info("Iteration: {d}", .{iter});
            var cluster = try Cluster.init(self.allocator, self.options.cluster, self.network);
            errdefer cluster.deinit();
            for (ticks_per_iteration) |_| {
                for (cluster_ticks_per_network_tick) |_| {
                    try cluster.tick();
                }
                try self.network.tick();
            }
            cluster.deinit();
            try self.network.reset();
        }
    }
};
