const std = @import("std");

const MessagePool = @import("../message_pool.zig").MessagePool;
const Message = MessagePool.Message;

pub const Path = struct {
    source: u8,
    target: u8,
};

pub fn NetworkSimulator(comptime Packet: type, comptime SimulatorType: anytype) type {
    const Simulator = SimulatorType(Packet);

    return struct {
        const Self = @This();

        const LinkPacket = struct {
            expiry: u64,
            callback: *const fn (packet: Packet, path: Path) void,
            packet: Packet,
        };

        links: *std.AutoHashMap(u32, std.ArrayList(LinkPacket)),
        simulator_ticker: Simulator,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var simulator_ticker = try Simulator.init(allocator);
            errdefer simulator_ticker.deinit();

            var links = std.AutoHashMap(u32, std.ArrayList(LinkPacket)).init(allocator);

            return Self{
                .links = &links,
                .simulator_ticker = simulator_ticker,
            };
        }

        pub fn deinit(self: *Self) void {
            const allocator = std.heap.page_allocator;
            var it = self.links.iterator();
            while (it.next()) |entry| {
                entry.value.deinit(allocator);
            }
            self.links.deinit();
        }

        pub fn add_link(self: *Self, process_id: u32) !void {
            if (!self.links.contains(process_id)) {
                const packet_queue = try std.ArrayList(*Message).init(std.heap.page_allocator);
                try self.links.put(process_id, packet_queue);
            }
        }

        pub fn submit_packet(
            self: *Self,
            packet: Packet, // Callee owned.
            callback: *const fn (packet: Packet, path: Path) void,
            path: Path,
        ) !void {
            var packet_queue = try self.links.get(path.target);
            try packet_queue.append(LinkPacket{ .callback = callback, .packet = packet, .path = path });
        }

        pub fn tick(self: *Self) void {
            self.simulator_ticker.tick(self.links);
        }
    };
}

// Delivers all packets to their destinations.
pub fn SimpleSimulatorType(comptime LinkPacket: type) type {
    return struct {
        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) !Self {
            _ = allocator;
            return Self{};
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub fn tick(links: *std.AutoHashMap(u32, std.ArrayList(LinkPacket))) void {
            var it = links.iterator();
            while (it.next()) |entry| {
                const packet_queue = entry.value;
                for (packet_queue.items) |packet| {
                    packet.callback(packet.packet, packet.path);
                }
                packet_queue.clear();
            }
        }
    };
}
