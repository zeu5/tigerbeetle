const std = @import("std");
const mem = std.mem;
const rand = std.rand;
const assert = std.debug.assert;
const log = std.log.scoped(.cluster);

const constants = @import("../../constants.zig");
const Storage = @import("../storage.zig").Storage;
const StorageFaultAtlas = @import("../storage.zig").ClusterFaultAtlas;
const AOF = @import("../aof.zig").AOF;
const MessagePool = @import("../../message_pool.zig").MessagePool;

const vsr = @import("../../vsr.zig");
const SuperBlock = vsr.SuperBlockType(Storage);
const MessageBus = @import("network.zig").MessageBus;
const Time = @import("../time.zig").Time;
const Network = @import("network.zig").Network;

pub const ReplicaStatus = enum { up, down };

// Cluster is a collection of replicas and clients.
// It is responsible for starting and stopping the replicas and clients.
// It also provides a way to get the event trace from the replicas.
// It uses the network to send messages between the replicas and clients.
pub fn ClusterType(comptime StateMachineType: anytype) type {
    return struct {
        const Self = @This();

        pub const StateMachine = StateMachineType(Storage, constants.state_machine_config);
        pub const Replica = vsr.ReplicaType(StateMachine, MessageBus, Storage, Time, AOF);
        pub const Client = vsr.Client(StateMachine, MessageBus);
        pub const Options = struct {
            cluster_id: u128,
            replica_count: u8,
            client_count: u8,
            storage_size_limit: u64,
            storage: Storage.Options,
            storage_fault_atlas: StorageFaultAtlas.Options,
            state_machine: StateMachine.Options,
            seed: u64,
        };

        pub fn default_options() Options {
            return .{
                .cluster_id = 0,
                .replica_count = 3,
                .client_count = 1,
                .storage_size_limit = 1 * constants.sector_size,
                .storage = .{
                    .seed = 0,
                    .read_latency_min = 1,
                    .read_latency_mean = 3,
                    .write_latency_min = 1,
                    .write_latency_mean = 13,
                    .read_fault_probability = 2,
                    .write_fault_probability = 2,
                    .crash_fault_probability = 82,
                },
                .storage_fault_atlas = .{
                    .faulty_superblock = true,
                    .faulty_wal_headers = true,
                    .faulty_wal_prepares = true,
                    .faulty_client_replies = true,
                    .faulty_grid = true,
                },
                .state_machine = .{ .lsm_forest_node_count = 4096 },
                .seed = 0,
            };
        }

        replica_count: u8,
        allocator: mem.Allocator,
        replicas: []Replica,
        replica_pools: []MessagePool,
        aofs: []AOF,
        clients: []Client,
        client_pools: []MessagePool,
        network: *Network,
        storages: []Storage,
        storage_fault_atlas: *StorageFaultAtlas,
        options: Options,
        replica_status: []ReplicaStatus,

        event_trace: std.ArrayList(vsr.ReplicaEvent),
        // state_trace: std.ArrayList([]vsr.VSRState),

        pub fn init(
            allocator: mem.Allocator,
            options: Options,
            network: *Network,
        ) !*Self {
            log.info("Creating cluster", .{});
            assert(options.replica_count >= 1);
            assert(options.client_count >= 1);
            assert(options.storage_size_limit % constants.sector_size == 0);
            assert(options.storage_size_limit <= constants.storage_size_limit_max);
            assert(options.storage.replica_index == null);
            assert(options.storage.fault_atlas == null);

            var prng = rand.DefaultPrng.init(options.seed);
            const random = prng.random();

            var replicas = try allocator.alloc(Replica, options.replica_count);
            errdefer allocator.free(replicas);

            const replica_status = try allocator.alloc(ReplicaStatus, options.replica_count);
            errdefer allocator.free(replica_status);
            @memset(replica_status, .up);

            var client_pools = try allocator.alloc(MessagePool, options.client_count);
            errdefer allocator.free(client_pools);

            for (client_pools, 0..) |*pool, i| {
                errdefer for (client_pools[0..i]) |*p| p.deinit(allocator);
                pool.* = try MessagePool.init(allocator, .client);
            }
            errdefer for (client_pools) |*pool| pool.deinit(allocator);

            var clients = try allocator.alloc(Client, options.client_count);
            errdefer allocator.free(clients);

            var event_trace = try std.ArrayList(vsr.ReplicaEvent).initCapacity(allocator, 100);
            // var state_trace = try std.ArrayList([]vsr.VSRState).initCapacity(allocator, 100);

            for (clients, 0..) |*client, i| {
                errdefer for (clients[0..i]) |*c| c.deinit(allocator);
                client.* = try Client.init(
                    allocator,
                    i,
                    options.cluster_id,
                    options.replica_count,
                    &client_pools[i],
                    .{ .network = network },
                );
                network.link(&client.message_bus, client.message_bus.process);
            }
            errdefer for (clients) |*client| client.deinit(allocator);

            var storage_fault_atlas = try allocator.create(StorageFaultAtlas);
            errdefer allocator.destroy(storage_fault_atlas);

            storage_fault_atlas.* = StorageFaultAtlas.init(
                options.replica_count,
                random,
                options.storage_fault_atlas,
            );

            const storages = try allocator.alloc(Storage, options.replica_count);
            errdefer allocator.free(storages);

            for (storages, 0..) |*storage, replica_index| {
                errdefer for (storages[0..replica_index]) |*s| s.deinit(allocator);
                var storage_options = options.storage;
                storage_options.replica_index = @as(u8, @intCast(replica_index));
                storage_options.fault_atlas = storage_fault_atlas;
                storage.* = try Storage.init(allocator, options.storage_size_limit, storage_options);
                // Disable most faults at startup, so that the replicas don't get stuck recovering_head.
                storage.faulty = replica_index >= vsr.quorums(options.replica_count).view_change;

                var superblock = try SuperBlock.init(allocator, .{
                    .storage = storage,
                    .storage_size_limit = options.storage_size_limit,
                });
                defer superblock.deinit(allocator);

                try vsr.format(
                    Storage,
                    allocator,
                    .{
                        .cluster = options.cluster_id,
                        .replica = @as(u8, @intCast(replica_index)),
                        .replica_count = options.replica_count,
                    },
                    storage,
                    &superblock,
                );
            }
            errdefer for (storages) |*storage| storage.deinit(allocator);

            var replica_pools = try allocator.alloc(MessagePool, options.replica_count);
            errdefer allocator.free(replica_pools);

            for (replica_pools, 0..) |*pool, i| {
                errdefer for (replica_pools[0..i]) |*p| p.deinit(allocator);
                pool.* = try MessagePool.init(allocator, .replica);
            }
            errdefer for (replica_pools) |*pool| pool.deinit(allocator);

            const aofs = try allocator.alloc(AOF, options.replica_count);
            errdefer allocator.free(aofs);

            for (aofs, 0..) |*aof, i| {
                errdefer for (aofs[0..i]) |*a| a.deinit(allocator);
                aof.* = try AOF.init(allocator);
            }
            errdefer for (aofs) |*aof| aof.deinit(allocator);

            var cluster = try allocator.create(Self);
            errdefer allocator.destroy(cluster);
            cluster.* = Self{
                .allocator = allocator,
                .replica_count = options.replica_count,
                .replicas = replicas,
                .replica_pools = replica_pools,
                .aofs = aofs,
                .clients = clients,
                .client_pools = client_pools,
                .network = network,
                .storages = storages,
                .storage_fault_atlas = storage_fault_atlas,
                .options = options,
                .replica_status = replica_status,
                .event_trace = event_trace,
                // .state_trace = state_trace,
            };

            for (cluster.replicas, 0..) |_, replica_index| {
                errdefer for (replicas[0..replica_index]) |*r| r.deinit(allocator);
                const nonce = 1 + @as(u128, replica_index) << 64;
                try cluster.open_replica(@as(u8, @intCast(replica_index)), nonce, .{
                    .resolution = constants.tick_ms * std.time.ns_per_ms,
                    .offset_type = .linear,
                    .offset_coefficient_A = 0,
                    .offset_coefficient_B = 0,
                });
            }
            errdefer for (cluster.replicas) |*replica| replica.deinit(allocator);

            return cluster;
        }

        fn open_replica(cluster: *Self, replica_index: u8, nonce: u128, time: Time) !void {
            var replica = &cluster.replicas[replica_index];
            try replica.open(cluster.allocator, .{
                .node_count = cluster.options.replica_count,
                .storage = &cluster.storages[replica_index],
                .aof = &cluster.aofs[replica_index],
                .storage_size_limit = cluster.options.storage_size_limit,
                .message_pool = &cluster.replica_pools[replica_index],
                .nonce = nonce,
                .time = time,
                .state_machine_options = cluster.options.state_machine,
                .message_bus_options = .{ .network = cluster.network },
            });
            assert(replica.cluster == cluster.options.cluster_id);
            assert(replica.replica == replica_index);
            assert(replica.replica_count == cluster.replica_count);

            cluster.network.link(&replica.message_bus, replica.message_bus.process);
            replica.test_context = cluster;
            replica.event_callback = on_replica_event;
        }

        fn on_replica_event(replica: *const Replica, event: vsr.ReplicaEvent) void {
            const cluster: *Self = @ptrCast(@alignCast(replica.test_context.?));
            assert(cluster.replica_status[replica.replica] == .up);

            if (cluster.event_trace.items.len == cluster.event_trace.capacity) {
                cluster.event_trace.ensureTotalCapacity(cluster.event_trace.capacity * 2) catch return;
            }
            cluster.event_trace.appendAssumeCapacity(event);
        }

        // pub fn get_state_trace(cluster: *Self) !std.ArrayList([]vsr.VSRState) {
        //     return cluster.state_trace;
        // }

        pub fn get_event_trace(cluster: *Self) !std.ArrayList(vsr.ReplicaEvent) {
            return cluster.event_trace;
        }

        pub fn get_replica(cluster: *Self, replica_id: u8) ?*Replica {
            if ((replica_id < 0) || (replica_id > cluster.options.replica_count)) {
                return null;
            }
            return &cluster.replicas[replica_id];
        }

        pub fn restart_replica(cluster: *Self, replica_id: u8) !void {
            // TODO: complete this
            if ((replica_id < 0) || (replica_id > cluster.options.replica_count)) {
                return;
            }
            if (cluster.replica_status[replica_id] != .down) {
                return;
            }
            cluster.replica_status[replica_id] = .up;
        }

        pub fn stop_replica(cluster: *Self, replica_id: u8) !void {
            // TODO: complete this
            if ((replica_id < 0) || (replica_id > cluster.options.replica_count)) {
                return;
            }
            cluster.replica_status[replica_id] = .down;
        }

        pub fn deinit(cluster: *Self) void {
            for (cluster.clients) |*client| client.deinit(cluster.allocator);
            for (cluster.client_pools) |*pool| pool.deinit(cluster.allocator);
            for (cluster.replicas, 0..) |*replica, i| {
                switch (cluster.replica_status[i]) {
                    .up => replica.deinit(cluster.allocator),
                    .down => {},
                }
            }
            for (cluster.replica_pools) |*pool| pool.deinit(cluster.allocator);
            for (cluster.aofs) |*aof| aof.deinit(cluster.allocator);
            for (cluster.storages) |*storage| storage.deinit(cluster.allocator);
            cluster.event_trace.deinit();
            // for (cluster.state_trace) |*states| {
            //     cluster.allocator.free(states);
            // }
            // cluster.state_trace.deinit();
            cluster.allocator.free(cluster.replica_status);
            cluster.allocator.free(cluster.clients);
            cluster.allocator.free(cluster.client_pools);
            cluster.allocator.free(cluster.replicas);
            cluster.allocator.free(cluster.replica_pools);
            cluster.allocator.free(cluster.storages);
            cluster.allocator.free(cluster.aofs);
            cluster.allocator.destroy(cluster.storage_fault_atlas);
            cluster.allocator.destroy(cluster);
        }

        pub fn tick(cluster: *Self) !void {
            for (cluster.clients) |*client| {
                client.tick();
            }
            for (cluster.storages) |*storage| {
                storage.tick();
            }
            for (cluster.replicas) |*replica| {
                if (cluster.replica_status[replica.replica] == .up) {
                    replica.tick();
                }
            }

            // var states = try std.ArrayList(vsr.VSRState).initCapacity(cluster.allocator, cluster.replica_count);
            // for (cluster.replicas) |*replica| {
            //     // No trivial mechanism to fetch the state of the replica - need to figure this out.
            //     states.append(replica.state);
            // }

            // if (cluster.state_trace.items.len == cluster.state_trace.capacity) {
            //     try cluster.state_trace.ensureTotalCapacity(cluster.state_trace.capacity * 2);
            // }
            // cluster.state_trace.appendAssumeCapacity(states.toOwnedSlice());
        }
    };
}
