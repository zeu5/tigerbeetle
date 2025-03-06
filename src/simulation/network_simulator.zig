const std = @import("std");
const log = std.log.scoped(.network_simulator);

const MessagePool = @import("../message_pool.zig").MessagePool;
const Message = MessagePool.Message;

pub const Path = struct {
    source: u8,
    target: u8,
};

pub const SimulationType = enum {
    Simple,
    Guided,
};

pub const SimulatorOptions = struct {
    simulation_type: SimulationType,
    context: ?*anyopaque,
    message_send_handler: *const fn (context: ?*anyopaque, packet: *Message, path: Path) void,
    message_receive_handler: *const fn (context: ?*anyopaque, packet: *Message, path: Path) void,
    simulation_trace: ?[]SimulationChoice,
};

pub const SimulationChoice = struct {
    process: u32,
    count: u32,
};

pub fn NetworkSimulator(comptime Packet: type) type {
    return struct {
        const Self = @This();

        const LinkPacket = struct {
            path: Path,
            callback: *const fn (packet: Packet, path: Path) void,
            packet: Packet,
        };

        allocator: std.mem.Allocator,

        links: std.AutoHashMap(u32, std.ArrayList(LinkPacket)),
        options: SimulatorOptions,
        simulation_trace: std.ArrayList(SimulationChoice),

        pub fn init(allocator: std.mem.Allocator, options: SimulatorOptions) !Self {
            var trace = std.ArrayList(SimulationChoice).init(allocator);
            if (options.simulation_type == SimulationType.Guided) {
                if (options.simulation_trace == null) {
                    return error.InvalidArgument;
                }
                var i: usize = options.simulation_trace.?.len;
                while (i > 0) : (i -= 1) {
                    trace.append(options.simulation_trace.?[i]) catch {};
                }
            }
            return Self{
                .allocator = allocator,
                .links = std.AutoHashMap(u32, std.ArrayList(LinkPacket)).init(allocator),
                .options = options,
                .simulation_trace = trace,
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.links.iterator();
            while (it.next()) |entry| {
                for (entry.value_ptr.items) |link| {
                    link.packet.deinit();
                }
                entry.value_ptr.deinit();
            }
            self.links.deinit();
            self.simulation_trace.deinit();
        }

        pub fn add_link(self: *Self, process_id: u32) void {
            if (!self.links.contains(process_id)) {
                self.links.put(process_id, std.ArrayList(LinkPacket).init(self.allocator)) catch {};
            }
        }

        pub fn submit_packet(
            self: *Self,
            packet: Packet, // Callee owned.
            callback: *const fn (packet: Packet, path: Path) void,
            path: Path,
        ) void {
            if (!self.links.contains(path.target)) {
                self.add_link(path.target);
            }
            var packet_queue = self.links.get(path.target).?;
            packet_queue.append(LinkPacket{
                .callback = callback,
                .packet = packet,
                .path = path,
            }) catch {
                log.debug("Failed to add packet to link. from={} to={} message={}", .{
                    path.source,
                    path.target,
                    packet.command(),
                });
            };
            self.links.put(path.target, packet_queue) catch {};
            self.options.message_send_handler(self.options.context, packet.message, path);
        }

        pub fn tick(self: *Self) void {
            switch (self.options.simulation_type) {
                SimulationType.Simple => self.tick_simple(),
                SimulationType.Guided => self.tick_guided(),
            }
        }

        pub fn tick_simple(self: *Self) void {
            var it = self.links.iterator();
            while (it.next()) |entry| {
                const packet_queue = entry.value_ptr;
                for (packet_queue.items) |packet| {
                    log.debug("Delivering packet. from={} to={} message={}", .{
                        packet.path.source,
                        packet.path.target,
                        packet.packet.command(),
                    });
                    defer packet.packet.deinit();
                    packet.callback(packet.packet, packet.path);
                    self.options.message_receive_handler(self.options.context, packet.packet.message, packet.path);
                }
                packet_queue.clearRetainingCapacity();
            }
        }

        pub fn tick_guided(self: *Self) void {
            if (self.simulation_trace.items.len == 0) {
                return;
            }
            const choice = self.simulation_trace.pop();
            if (!self.links.contains(choice.process)) {
                return;
            }
            const it = self.links.get(choice.process);
            if (it) |packet_queue_orig| {
                var count = choice.count;
                var packet_queue = packet_queue_orig;
                while (count > 0 and packet_queue.items.len > 0) {
                    const packet = packet_queue.items[0];
                    log.debug("Delivering packet. from={} to={} message={}", .{
                        packet.path.source,
                        packet.path.target,
                        packet.packet.command(),
                    });
                    defer packet.packet.deinit();
                    packet.callback(packet.packet, packet.path);
                    self.options.message_receive_handler(self.options.context, packet.packet.message, packet.path);
                    packet_queue.items = packet_queue.items[1..];
                    count -= 1;
                }
                self.links.put(choice.process, packet_queue) catch {};
            }
        }
    };
}
