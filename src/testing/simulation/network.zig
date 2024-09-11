// Structure to create message busses for all processes
//  MessageBus {
//      pool: MessagePool
//      Options - config
//      init(mem.Allocator, u128, Process, *MessagePool, on_message_callback, Options)
//      deinit(mem.Allocator)
//      tick()
//      get_message(?vsr.Command)
//      unref(message)
//      send_message_to_replica(u8, message)
//      send_message_to_client(u128, message)
//  }
//
// Network should use this MessageBus to send and receive messages
const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const stdx = @import("../../stdx.zig");
const MessagePool = @import("../../message_pool.zig").MessagePool;
const Message = MessagePool.Message;
const vsr = @import("../../vsr.zig");
const ProcessType = vsr.ProcessType;
const types = @import("types.zig");

const Scheduler = @import("scheduler.zig").Scheduler;
const SchedulerTickResult = @import("scheduler.zig").TickResult;

// MessageBus is a structure that manages the sending and receiving of messages.
// It is tied to a single process, and can only send messages to other processes.
pub const MessageBus = struct {
    network: *Network,
    pool: *MessagePool,

    cluster: u128,
    process: types.Process,

    /// The callback to be called when a message is received.
    on_message_callback: *const fn (message_bus: *MessageBus, message: *Message) void,

    pub const Options = struct {
        network: *Network,
    };

    pub fn init(
        _: std.mem.Allocator,
        cluster: u128,
        process: types.Process,
        message_pool: *MessagePool,
        on_message_callback: *const fn (message_bus: *MessageBus, message: *Message) void,
        options: Options,
    ) !MessageBus {
        return MessageBus{
            .network = options.network,
            .pool = message_pool,
            .cluster = cluster,
            .process = process,
            .on_message_callback = on_message_callback,
        };
    }

    /// TODO
    pub fn deinit(_: *MessageBus, _: std.mem.Allocator) void {}

    pub fn tick(_: *MessageBus) void {}

    pub fn get_message(
        bus: *MessageBus,
        comptime command: ?vsr.Command,
    ) MessagePool.GetMessageType(command) {
        return bus.pool.get_message(command);
    }

    /// `@TypeOf(message)` is one of:
    /// - `*Message`
    /// - `MessageType(command)` for any `command`.
    pub fn unref(bus: *MessageBus, message: anytype) void {
        bus.pool.unref(message);
    }

    pub fn send_message_to_replica(bus: *MessageBus, replica: u8, message: *Message) void {
        // Messages sent by a process to itself should never be passed to the message bus
        // TODO: get rid of this?
        if (bus.process == .replica) assert(replica != bus.process.replica);

        bus.network.send_message(message, .{
            .source = bus.process,
            .target = .{ .replica = replica },
        });
    }

    /// Try to send the message to the client with the given id.
    /// If the client is not currently connected, the message is silently dropped.
    pub fn send_message_to_client(bus: *MessageBus, client_id: u128, message: *Message) void {
        assert(bus.process == .replica);

        bus.network.send_message(message, .{
            .source = bus.process,
            .target = .{ .client = client_id },
        });
    }

    pub fn receive_message(bus: *MessageBus, message: *Message) void {
        bus.on_message_callback(bus, message);
    }
};

// Network models the communication layer between two processes.
// It uses the scheduler to schedule messages to be sent or dropped.
// It is agnostic to the status of the process (replica or client).
pub const Network = struct {
    const Self = @This();

    pub const Options = struct {
        node_count: u8,
        client_count: u64,

        path_max_capacity: u8,
    };

    allocator: mem.Allocator,
    scheduler: *Scheduler,
    options: Options,
    in_transit_messages: MessagePool,
    busses: std.AutoHashMap(types.Process, *MessageBus),

    pub fn default_options() Options {
        return Options{
            .node_count = 3,
            .client_count = 1,
            .path_max_capacity = 10,
        };
    }

    pub fn init(
        allocator: mem.Allocator,
        options: Options,
        scheduler: *Scheduler,
    ) !*Self {
        var network = try allocator.create(Self);
        errdefer allocator.destroy(network);

        var busses = std.AutoHashMap(types.Process, *MessageBus).init(allocator);
        try busses.ensureTotalCapacity(@intCast(options.node_count + options.client_count + 2));
        errdefer busses.deinit();

        var path_count = options.node_count * (options.node_count - 1) + 2 * options.client_count;
        var in_transit_messages = try MessagePool.init_capacity(
            allocator,
            @as(usize, path_count * options.path_max_capacity),
        );

        network.* = Self{
            .allocator = allocator,
            .scheduler = scheduler,
            .options = options,
            .busses = busses,
            .in_transit_messages = in_transit_messages,
        };

        return network;
    }

    pub fn deinit(network: *Self) void {
        network.busses.deinit();
        network.allocator.destroy(network);
    }

    pub fn send_message(network: *Self, message: *Message, message_info: types.MessageInfo) void {
        const message_copy = network.in_transit_messages.get_message(null);
        stdx.copy_disjoint(.exact, u8, message_copy.buffer, message.buffer);

        network.scheduler.add_message(message_copy, message_info);
    }

    pub fn tick(network: *Self) !void {
        var scheduler_tickresult: SchedulerTickResult = try network.scheduler.tick();
        if (scheduler_tickresult.to_deliver) |messages| {
            for (messages) |message| {
                var message_info = message.info;
                var bus = network.busses.get(message_info.target);
                if (bus) |b| {
                    b.receive_message(message.message);
                }
                network.in_transit_messages.unref(message.message);
            }
        }
        if (scheduler_tickresult.to_drop) |messages| {
            for (messages) |message| {
                network.in_transit_messages.unref(message.message);
            }
        }
    }

    // Write a link function that accepts a message bus and process and returns nothing
    pub fn link(network: *Self, bus: *MessageBus, process: types.Process) void {
        network.busses.putAssumeCapacity(process, bus);
    }

    pub fn unlink(network: *Self, process: types.Process) void {
        network.busses.remove(process);
    }

    pub fn unlinlk_all(network: *Self) void {
        network.busses.clearRetainingCapacity();
    }

    pub fn reset(network: *Self) !void {
        network.in_transit_messages.deinit(network.allocator);

        var options = network.options;
        var path_count = options.node_count * (options.node_count - 1) + 2 * options.client_count;
        var in_transit_messages = try MessagePool.init_capacity(
            network.allocator,
            path_count * options.path_max_capacity,
        );
        network.in_transit_messages = in_transit_messages;

        network.busses.clearRetainingCapacity();
        network.scheduler.reset();
    }
};
