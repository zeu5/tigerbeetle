// Network type
// 1. link(process, message_bus)
// 2. init(allocator: mem.Allocator, options: Options) !Network
// 3. deinit(network: *Network, allocator: mem.Allocator) void
// 4. tick(network: *Network) void
// 5. process_disable(process: Process) void
// 6. get_message_bus(process: Process) *MessageBus
// 7. process_enable(process: Process) void
// 8. send_message(message, path)

// pub const Path = struct {
//     source: Process,
//     target: Process,
// };

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const constants = @import("../constants.zig");
const vsr = @import("../vsr.zig");
const stdx = @import("../stdx.zig");

const MessagePool = @import("../message_pool.zig").MessagePool;
const Message = MessagePool.Message;

const MessageBus = @import("message_bus.zig").MessageBus;
const Process = @import("message_bus.zig").Process;

const NetworkSimulator = @import("network_simulator.zig").NetworkSimulator;
const NetworkSimulatorOptions = @import("network_simulator.zig").SimulatorOptions;
const NetworkSimulatorPath = @import("network_simulator.zig").Path;

const log = std.log.scoped(.network);

pub const NetworkOptions = struct {
    node_count: u8,
    client_count: u8,
    seed: u64,
    simulation_options: NetworkSimulatorOptions,
    path_maximum_capacity: u8,
    recorded_count_max: u8,
};

pub const Path = struct {
    source: Process,
    target: Process,
};

pub const Network = struct {
    pub const Packet = struct {
        network: *Network,
        message: *Message,

        pub fn clone(packet: *const Packet) Packet {
            return Packet{
                .network = packet.network,
                .message = packet.message.ref(),
            };
        }

        pub fn deinit(packet: *const Packet) void {
            packet.network.message_pool.unref(packet.message);
        }

        pub fn command(packet: *const Packet) vsr.Command {
            return packet.message.header.command;
        }
    };

    /// Core is a strongly-connected component of replicas containing a view change quorum.
    /// It is used to define and check liveness --- if a core exists, it should converge
    /// to normal status in a bounded number of ticks.
    ///
    /// At the moment, we require core members to have direct bidirectional connectivity, but this
    /// could be relaxed in the future to indirect connectivity.
    pub const Core = std.StaticBitSet(constants.members_max);

    allocator: std.mem.Allocator,
    network_simulator: NetworkSimulator(Packet),

    buses: std.ArrayListUnmanaged(*MessageBus),
    buses_enabled: std.ArrayListUnmanaged(bool),
    processes: std.ArrayListUnmanaged(u128),
    /// A pool of messages that are in the network (sent, but not yet delivered).
    message_pool: MessagePool,
    options: NetworkOptions,

    pub fn init(
        allocator: std.mem.Allocator,
        options: NetworkOptions,
    ) !Network {
        const process_count = options.client_count + options.node_count;

        var buses = try std.ArrayListUnmanaged(*MessageBus).initCapacity(allocator, process_count);
        errdefer buses.deinit(allocator);

        var buses_enabled = try std.ArrayListUnmanaged(bool).initCapacity(allocator, process_count);
        errdefer buses_enabled.deinit(allocator);

        var processes = try std.ArrayListUnmanaged(u128).initCapacity(allocator, process_count);
        errdefer processes.deinit(allocator);

        var packet_simulator = try NetworkSimulator(Packet).init(allocator, options.simulation_options);
        errdefer packet_simulator.deinit();

        // Count:
        // - replica → replica paths (excluding self-loops)
        // - replica → client paths
        // - client → replica paths
        // but not client→client paths; clients never message one another.
        const node_count = @as(usize, options.node_count);
        const client_count = @as(usize, options.client_count);
        const path_count = node_count * (node_count - 1) + 2 * node_count * client_count;
        const message_pool = try MessagePool.init_capacity(
            allocator,
            // +1 so we can allocate an extra packet when all packet queues are at capacity,
            // so that `PacketSimulator.submit_packet` can choose which packet to drop.
            1 + @as(usize, options.path_maximum_capacity) * path_count +
                options.recorded_count_max,
        );
        errdefer message_pool.deinit(allocator);

        return Network{
            .allocator = allocator,
            .options = options,
            .network_simulator = packet_simulator,
            .buses = buses,
            .buses_enabled = buses_enabled,
            .processes = processes,
            .message_pool = message_pool,
        };
    }

    pub fn deinit(network: *Network) void {
        network.buses.deinit(network.allocator);
        network.buses_enabled.deinit(network.allocator);
        network.processes.deinit(network.allocator);
        network.network_simulator.deinit();
        network.message_pool.deinit(network.allocator);
    }

    pub fn tick(network: *Network) void {
        network.network_simulator.tick();
    }

    pub fn link(network: *Network, process: Process, message_bus: *MessageBus) void {
        const raw_process = switch (process) {
            .replica => |replica| replica,
            .client => |client| blk: {
                assert(client >= constants.members_max);
                break :blk client;
            },
        };

        for (network.processes.items, 0..) |existing_process, i| {
            if (existing_process == raw_process) {
                network.buses.items[i] = message_bus;
                break;
            }
        } else {
            // PacketSimulator assumes that replicas go first.
            switch (process) {
                .replica => assert(network.processes.items.len < network.options.node_count),
                .client => assert(network.processes.items.len >= network.options.node_count),
            }
            network.processes.appendAssumeCapacity(raw_process);
            network.buses.appendAssumeCapacity(message_bus);
            network.buses_enabled.appendAssumeCapacity(true);
        }
        assert(network.processes.items.len == network.buses.items.len);
    }

    pub fn process_enable(network: *Network, process: Process) void {
        assert(!network.buses_enabled.items[network.process_to_address(process)]);
        network.buses_enabled.items[network.process_to_address(process)] = true;
    }

    pub fn process_disable(network: *Network, process: Process) void {
        assert(network.buses_enabled.items[network.process_to_address(process)]);
        network.buses_enabled.items[network.process_to_address(process)] = false;
    }

    pub fn link_clear(network: *Network, path: Path) void {
        network.network_simulator.link_clear(.{
            .source = network.process_to_address(path.source),
            .target = network.process_to_address(path.target),
        });
    }

    pub fn send_message(network: *Network, message: *Message, path: Path) void {
        log.debug("send_message: {} > {}: {}", .{
            path.source,
            path.target,
            message.header.command,
        });

        const peer_type = message.header.peer_type();
        if (peer_type != .unknown) {
            switch (path.source) {
                .client => |client_id| assert(std.meta.eql(peer_type, .{ .client = client_id })),
                .replica => |index| assert(std.meta.eql(peer_type, .{ .replica = index })),
            }
        }

        const network_message = network.message_pool.get_message(null);
        defer network.message_pool.unref(network_message);

        stdx.copy_disjoint(.exact, u8, network_message.buffer, message.buffer);

        network.network_simulator.submit_packet(
            .{
                .message = network_message.ref(),
                .network = network,
            },
            deliver_message,
            .{
                .source = network.process_to_address(path.source),
                .target = network.process_to_address(path.target),
            },
        );
    }

    fn process_to_address(network: *const Network, process: Process) u8 {
        for (network.processes.items, 0..) |p, i| {
            if (std.meta.eql(raw_process_to_process(p), process)) {
                switch (process) {
                    .replica => assert(i < network.options.node_count),
                    .client => assert(i >= network.options.node_count),
                }
                return @intCast(i);
            }
        }
        log.err("no such process: {} (have {any})", .{ process, network.processes.items });
        unreachable;
    }

    pub fn get_message_bus(network: *Network, process: Process) *MessageBus {
        return network.buses.items[network.process_to_address(process)];
    }

    fn deliver_message(packet: Packet, path: NetworkSimulatorPath) void {
        const network = packet.network;
        const process_path = .{
            .source = raw_process_to_process(network.processes.items[path.source]),
            .target = raw_process_to_process(network.processes.items[path.target]),
        };

        if (!network.buses_enabled.items[path.target]) {
            log.debug("deliver_message: {} > {}: {} (dropped; target is down)", .{
                process_path.source,
                process_path.target,
                packet.message.header.command,
            });
            return;
        }

        const target_bus = network.buses.items[path.target];
        const target_message = target_bus.get_message(null);
        defer target_bus.unref(target_message);

        stdx.copy_disjoint(.exact, u8, target_message.buffer, packet.message.buffer);

        log.debug("deliver_message: {} > {}: {}", .{
            process_path.source,
            process_path.target,
            packet.message.header.command,
        });

        if (target_message.header.command == .request or
            target_message.header.command == .prepare or
            target_message.header.command == .block)
        {
            const sector_ceil = vsr.sector_ceil(target_message.header.size);
            if (target_message.header.size != sector_ceil) {
                assert(target_message.header.size < sector_ceil);
                assert(target_message.buffer.len == constants.message_size_max);
                @memset(target_message.buffer[target_message.header.size..sector_ceil], 0);
            }
        }

        target_bus.on_message_callback(target_bus, target_message);
    }

    fn raw_process_to_process(raw: u128) Process {
        switch (raw) {
            0...(constants.members_max - 1) => return .{ .replica = @intCast(raw) },
            else => {
                assert(raw >= constants.members_max);
                return .{ .client = raw };
            },
        }
    }
};
