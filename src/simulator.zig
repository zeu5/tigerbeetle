const std = @import("std");
const flags = @import("./flags.zig");
const vsr = @import("./vsr.zig");
const constants = @import("./constants.zig");
const Header = vsr.Header;

const StateMachineType = @import("simulation/state_machine.zig").StateMachineType;
const StateMachine = Cluster.StateMachine;

const Cluster = @import("simulation/cluster.zig").ClusterType(StateMachineType);
const Orchestrator = @import("simulation/orchestrator.zig").Orchestrator;
const Release = @import("simulation/cluster.zig").Release;
const message_trace_recorder = @import("simulation/message_trace_recorder.zig");
const MessageTraceRecorder = message_trace_recorder.MessageTraceRecorder;

const CLIArgs = struct {
    ticks_max_requests: u32 = 1000,
    positional: struct {
        seed: ?[]const u8 = null,
    },
};

pub const std_options = .{
    .log_level = .info,
};

const releases = [_]Release{
    .{
        .release = vsr.Release.from(.{ .major = 0, .minor = 0, .patch = 1 }),
        .release_client_min = vsr.Release.from(.{ .major = 0, .minor = 0, .patch = 1 }),
    },
    .{
        .release = vsr.Release.from(.{ .major = 0, .minor = 0, .patch = 2 }),
        .release_client_min = vsr.Release.from(.{ .major = 0, .minor = 0, .patch = 1 }),
    },
    .{
        .release = vsr.Release.from(.{ .major = 0, .minor = 0, .patch = 3 }),
        .release_client_min = vsr.Release.from(.{ .major = 0, .minor = 0, .patch = 1 }),
    },
};

pub const output = std.log.scoped(.simulator);

pub fn main() !void {

    // This must be initialized at runtime as stderr is not comptime known on e.g. Windows.
    log_buffer.unbuffered_writer = std.io.getStdErr().writer();

    // TODO Use std.testing.allocator when all deinit() leaks are fixed.
    const allocator = std.heap.page_allocator;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const cli_args = flags.parse(&args, CLIArgs);

    const seed_random = std.crypto.random.int(u64);
    const seed = seed_from_arg: {
        const seed_argument = cli_args.positional.seed orelse break :seed_from_arg seed_random;
        break :seed_from_arg vsr.testing.parse_seed(seed_argument);
    };

    var prng = std.rand.DefaultPrng.init(seed);
    const random = prng.random();

    const replica_count = 3;
    const client_count = 1;
    const node_count = replica_count;
    const batch_size_limit = constants.message_body_size_max;

    const MiB = 1024 * 1024;
    const storage_size_limit = vsr.sector_floor(
        2048 * MiB,
    );

    const cluster_id = 0;
    const standby_count = 0;

    const trace_file_path = "trace.json";
    var trace_recorder = try MessageTraceRecorder.init(allocator, trace_file_path);

    const cluster_options = Cluster.Options{
        .cluster_id = cluster_id,
        .replica_count = replica_count,
        .standby_count = standby_count,
        .client_count = client_count,
        .storage_size_limit = storage_size_limit,
        .seed = random.int(u64),
        .releases = &releases,
        .client_release = releases[0].release,
        .network = .{
            .node_count = node_count,
            .client_count = client_count,
            .seed = random.int(u64),
            .path_maximum_capacity = 2,
            .recorded_count_max = 0,
            .simulation_options = .{
                .simulation_type = .Simple,
                .context = &trace_recorder,
                .message_send_handler = message_trace_recorder.send_handler,
                .message_receive_handler = message_trace_recorder.receive_handler,
                .simulation_trace = null,
            },
        },
        .storage = .{
            .read_latency_min = 0,
            .read_latency_mean = 0,
            .write_latency_min = 0,
            .write_latency_mean = 0,
        },
        .state_machine = .{
            .batch_size_limit = batch_size_limit,
            .lsm_forest_node_count = 4096,
        },
        .on_cluster_reply = Orchestrator.on_cluster_reply,
        .on_client_reply = Orchestrator.on_client_reply,
    };

    const workload_options = StateMachine.Workload.Options{
        .batch_size_limit = batch_size_limit,
    };

    const orchestrator_options = Orchestrator.Options{
        .cluster = cluster_options,
        .workload = workload_options,
        .requests_max = 10,
    };

    var orchestrator = try Orchestrator.init(allocator, random, orchestrator_options);
    defer orchestrator.deinit(allocator);

    for (0..orchestrator.cluster.clients.len) |client_index| {
        orchestrator.cluster.register(client_index);
    }

    // Safety: replicas crash and restart; at any given point in time arbitrarily many replicas may
    // be crashed, but each replica restarts eventually. The cluster must process all requests
    // without split-brain.
    var tick_total: u64 = 0;
    var tick: u64 = 0;
    while (tick < cli_args.ticks_max_requests) : (tick += 1) {
        const requests_replied_old = orchestrator.requests_replied;
        orchestrator.tick();
        tick_total += 1;
        if (orchestrator.requests_replied > requests_replied_old) {
            tick = 0;
        }
        const requests_done = orchestrator.requests_replied == orchestrator.options.requests_max;
        const upgrades_done =
            for (orchestrator.cluster.replicas, orchestrator.cluster.replica_health) |*replica, health|
        {
            if (health == .down) continue;
            const release_latest = releases[orchestrator.replica_releases_limit - 1].release;
            if (replica.release.value == release_latest.value) {
                break true;
            }
        } else false;

        if (requests_done and upgrades_done) break;
    }
    trace_recorder.record_trace() catch |err| {
        output.info("failed to record trace: {}", .{err});
    };
}

var log_buffer: std.io.BufferedWriter(4096, std.fs.File.Writer) = .{
    // This is initialized in main(), as std.io.getStdErr() is not comptime known on e.g. Windows.
    .unbuffered_writer = undefined,
};
