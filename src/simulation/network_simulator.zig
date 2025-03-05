const std = @import("std");

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

        links: *std.AutoHashMap(u32, std.ArrayList(LinkPacket)),
        options: SimulatorOptions,

        pub fn init(allocator: std.mem.Allocator, options: SimulatorOptions) !Self {
            var links = std.AutoHashMap(u32, std.ArrayList(LinkPacket)).init(allocator);

            return Self{
                .allocator = allocator,
                .links = &links,
                .options = options,
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.links.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.links.deinit();
        }

        pub fn add_link(self: *Self, process_id: u32) void {
            if (!self.links.contains(process_id)) {
                const packet_queue = std.ArrayList(*Message).init(self.allocator);
                self.links.put(process_id, packet_queue);
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
            var packet_queue = self.links.get(path.target);
            packet_queue.append(LinkPacket{
                .callback = callback,
                .packet = packet,
                .path = path,
            });
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
                    packet.callback(packet.packet, packet.path);
                }
                packet_queue.clearRetainingCapacity();
            }
        }

        pub fn tick_guided(self: *Self) void {
            _ = self;
            // TODO
        }
    };
}
