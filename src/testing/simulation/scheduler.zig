const std = @import("std");
const mem = std.mem;
const MessagePool = @import("../../message_pool.zig").MessagePool;
const Message = MessagePool.Message;

pub const TickResult = struct {
    to_deliver: ?[]*Message,
    to_drop: ?[]*Message,
};

pub const Scheduler = struct {
    const Self = @This();

    allocator: mem.Allocator,
    messages: []*Message,

    pub fn init(allocator: mem.Allocator) !*Scheduler {
        var scheduler = try allocator.create(Self);
        errdefer allocator.destroy(scheduler);

        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(scheduler: *Self) void {
        scheduler.allocator.destroy(scheduler);
    }

    pub fn reset(scheduler: *Self) void {
        _ = scheduler;
    }

    pub fn tick(scheduler: *Self) TickResult {
        _ = scheduler;
        return TickResult{
            .to_deliver = null,
            .to_drop = null,
        };
    }
};
