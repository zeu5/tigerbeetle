// A high level orchestrator that initializes the cluster, network
// and runs the simulation iteration by iteration.

// We can have types for the orchestrator
// 1. Simple - Standard network that delivers everything
// 2. Random - Random network that picks the order of delivery of messages
// 3. Guided - Network that delivers messages as guided by the user
const std = @import("std");
const stdx = @import("../stdx.zig");
const builtin = @import("builtin");

const assert = std.debug.assert;
const maybe = stdx.maybe;
const mem = std.mem;

const constants = @import("../constants.zig");
const flags = @import("../flags.zig");
const schema = @import("../lsm/schema.zig");
const vsr = @import("../vsr.zig");
const Header = vsr.Header;

const StateMachineType = @import("state_machine.zig").StateMachineType;
const SimpleSimulatorType = @import("network_simulator.zig").SimpleSimulatorType;

const Cluster = @import("cluster.zig").ClusterType(StateMachineType, SimpleSimulatorType);
const StateMachine = Cluster.StateMachine;
const Message = @import("../message_pool.zig").MessagePool.Message;
const ReplySequence = @import("../testing/reply_sequence.zig").ReplySequence;

pub const output = std.log.scoped(.cluster);
const log = std.log.scoped(.orchestrator);

pub const Orchestrator = struct {
    pub const Options = struct {
        cluster: Cluster.Options,
        workload: StateMachine.Workload.Options,

        /// The total number of requests to send. Does not count `register` messages.
        requests_max: usize,
    };

    random: std.rand.Random,
    options: Options,
    cluster: *Cluster,
    workload: StateMachine.Workload,

    // The number of releases in each replica's "binary".
    replica_releases: []usize,
    /// The maximum number of releases available in any replica's "binary".
    /// (i.e. the maximum of any `replica_releases`.)
    replica_releases_limit: usize = 1,

    reply_op_next: u64 = 1, // Skip the root op.
    reply_sequence: ReplySequence,

    /// Total number of requests sent, including those that have not been delivered.
    /// Does not include `register` messages.
    requests_sent: usize = 0,
    /// Total number of replies received by non-evicted clients.
    /// Does not include `register` messages.
    requests_replied: usize = 0,
    requests_idle: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        random: std.rand.Random,
        options: Options,
    ) !Orchestrator {
        assert(options.requests_max > 0);

        var cluster = try Cluster.init(allocator, options.cluster);
        errdefer cluster.deinit();

        var workload = try StateMachine.Workload.init(allocator, random, options.workload);
        errdefer workload.deinit(allocator);

        const replica_releases = try allocator.alloc(
            usize,
            options.cluster.replica_count + options.cluster.standby_count,
        );
        errdefer allocator.free(replica_releases);
        @memset(replica_releases, 1);

        var reply_sequence = try ReplySequence.init(allocator);
        errdefer reply_sequence.deinit(allocator);

        return Orchestrator{
            .random = random,
            .options = options,
            .cluster = cluster,
            .workload = workload,
            .replica_releases = replica_releases,
            .reply_sequence = reply_sequence,
        };
    }

    pub fn deinit(orchestrator: *Orchestrator, allocator: std.mem.Allocator) void {
        allocator.free(orchestrator.replica_releases);
        orchestrator.reply_sequence.deinit(allocator);
        orchestrator.workload.deinit(allocator);
        orchestrator.cluster.deinit();
    }

    pub fn tick(orchestrator: *Orchestrator) void {
        // TODO(Zig): Remove (see on_cluster_reply()).
        orchestrator.cluster.context = orchestrator;

        orchestrator.cluster.tick();
        orchestrator.tick_requests();
    }

    fn requests_cancelled(orchestrator: *const Orchestrator) u32 {
        var count: u32 = 0;
        for (
            orchestrator.cluster.clients,
            orchestrator.cluster.client_eviction_reasons,
        ) |*client, reason| {
            count += @intFromBool(reason != null and
                client.request_inflight != null and
                client.request_inflight.?.message.header.operation != .register);
        }
        return count;
    }

    pub fn on_cluster_reply(
        cluster: *Cluster,
        reply_client: ?usize,
        prepare: *const Message.Prepare,
        reply: *const Message.Reply,
    ) void {
        assert((reply_client == null) == (prepare.header.client == 0));

        const orchestrator: *Orchestrator = @ptrCast(@alignCast(cluster.context.?));

        if (reply.header.op < orchestrator.reply_op_next) return;
        if (orchestrator.reply_sequence.contains(reply)) return;

        orchestrator.reply_sequence.insert(reply_client, prepare, reply);

        while (!orchestrator.reply_sequence.empty()) {
            const op = orchestrator.reply_op_next;
            const prepare_header = orchestrator.cluster.state_checker.commits.items[op].header;
            assert(prepare_header.op == op);

            if (orchestrator.reply_sequence.peek(op)) |commit| {
                defer orchestrator.reply_sequence.next();

                orchestrator.reply_op_next += 1;

                assert(commit.reply.references == 1);
                assert(commit.reply.header.op == op);
                assert(commit.reply.header.command == .reply);
                assert(commit.reply.header.request == commit.prepare.header.request);
                assert(commit.reply.header.operation == commit.prepare.header.operation);
                assert(commit.prepare.references == 1);
                assert(commit.prepare.header.checksum == prepare_header.checksum);
                assert(commit.prepare.header.command == .prepare);

                log.debug("consume_stalled_replies: op={} operation={} client={} request={}", .{
                    commit.reply.header.op,
                    commit.reply.header.operation,
                    commit.prepare.header.client,
                    commit.prepare.header.request,
                });

                if (prepare_header.operation == .pulse) {
                    orchestrator.workload.on_pulse(
                        prepare_header.operation.cast(StateMachine),
                        prepare_header.timestamp,
                    );
                }

                if (!commit.prepare.header.operation.vsr_reserved()) {
                    orchestrator.workload.on_reply(
                        commit.client_index.?,
                        commit.reply.header.operation.cast(StateMachine),
                        commit.reply.header.timestamp,
                        commit.prepare.body_used(),
                        commit.reply.body_used(),
                    );
                }
            }
        }
    }

    pub fn on_client_reply(
        cluster: *Cluster,
        reply_client: usize,
        request: *const Message.Request,
        reply: *const Message.Reply,
    ) void {
        _ = reply;

        const orchestrator: *Orchestrator = @ptrCast(@alignCast(cluster.context.?));
        assert(orchestrator.cluster.client_eviction_reasons[reply_client] == null);

        if (!request.header.operation.vsr_reserved()) {
            orchestrator.requests_replied += 1;
        }
    }

    /// Maybe send a request from one of the cluster's clients.
    fn tick_requests(orchestrator: *Orchestrator) void {
        if (orchestrator.requests_idle) return;
        if (orchestrator.requests_sent - orchestrator.requests_cancelled() ==
            orchestrator.options.requests_max) return;

        const client_index = index: {
            const client_count = orchestrator.options.cluster.client_count;
            const client_index_base =
                orchestrator.random.uintLessThan(usize, client_count);
            for (0..client_count) |offset| {
                const client_index = (client_index_base + offset) % client_count;
                if (orchestrator.cluster.client_eviction_reasons[client_index] == null) {
                    break :index client_index;
                }
            } else {
                for (0..client_count) |index| {
                    assert(orchestrator.cluster.client_eviction_reasons[index] != null);
                    assert(orchestrator.cluster.client_eviction_reasons[index] == .no_session or
                        orchestrator.cluster.client_eviction_reasons[index] == .session_too_low);
                }
                stdx.unimplemented("client replacement; all clients were evicted");
            }
        };

        var client = &orchestrator.cluster.clients[client_index];

        // Messages aren't added to the ReplySequence until a reply arrives.
        // Before sending a new message, make sure there will definitely be room for it.
        var reserved: usize = 0;
        for (orchestrator.cluster.clients) |*c| {
            // Count the number of clients that are still waiting for a `register` to complete,
            // since they may start one at any time.
            reserved += @intFromBool(c.session == 0);
            // Count the number of non-register requests queued.
            reserved += @intFromBool(c.request_inflight != null);
        }
        // +1 for the potential request — is there room in the sequencer's queue?
        if (reserved + 1 > orchestrator.reply_sequence.free()) return;

        // Make sure that the client is ready to send a new request.
        if (client.request_inflight != null) return;
        const request_message = client.get_message();
        errdefer client.release_message(request_message);

        const request_metadata = orchestrator.workload.build_request(
            client_index,
            request_message.buffer[@sizeOf(vsr.Header)..constants.message_size_max],
        );
        assert(request_metadata.size <= constants.message_size_max - @sizeOf(vsr.Header));

        orchestrator.cluster.request(
            client_index,
            request_metadata.operation,
            request_message,
            request_metadata.size,
        );
        // Since we already checked the client's request queue for free space, `client.request()`
        // should always queue the request.
        assert(request_message == client.request_inflight.?.message.base());
        assert(request_message.header.size == @sizeOf(vsr.Header) + request_metadata.size);
        assert(request_message.header.into(.request).?.operation.cast(StateMachine) ==
            request_metadata.operation);

        orchestrator.requests_sent += 1;
        assert(orchestrator.requests_sent - orchestrator.requests_cancelled() <=
            orchestrator.options.requests_max);
    }
};
