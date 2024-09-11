const std = @import("std");
const mem = std.mem;
const MessagePool = @import("../../message_pool.zig").MessagePool;
const Message = MessagePool.Message;
const types = @import("types.zig");
const log = std.log.scoped(.scheduler);

pub const TickResult = struct {
    to_deliver: ?[]types.MessageWrapper,
    to_drop: ?[]types.MessageWrapper,
};

pub const SchedulerType = enum(u8) {
    DeliverAll,
};

pub const SchedulerInitError = error{
    InvalidSchedulerType,
};

pub const Scheduler = struct {
    const Self = @This();

    pub const Options = struct {
        scheduler_type: []const u8,
        max_intransit_messages: u32,
    };

    pub fn default_options() Options {
        return Options{
            .scheduler_type = "deliver_all",
            .max_intransit_messages = 200,
        };
    }

    options: Options,
    allocator: mem.Allocator,
    messages: std.ArrayList(types.MessageWrapper),
    scheduler_type: SchedulerType,

    pub fn init(allocator: mem.Allocator, options: Options) !*Scheduler {
        log.info("Creating scheduler of type {s}", .{options.scheduler_type});
        var scheduler = try allocator.create(Self);
        errdefer allocator.destroy(scheduler);

        var messages = try std.ArrayList(types.MessageWrapper).initCapacity(allocator, @as(usize, options.max_intransit_messages));
        errdefer messages.deinit();

        var scheduler_type = SchedulerType.DeliverAll;
        if (std.mem.eql(u8, options.scheduler_type, "deliver_all")) {
            scheduler_type = SchedulerType.DeliverAll;
        } else {
            return SchedulerInitError.InvalidSchedulerType;
        }

        scheduler.* = Self{
            .allocator = allocator,
            .messages = messages,
            .options = options,
            .scheduler_type = scheduler_type,
        };
        return scheduler;
    }

    pub fn deinit(scheduler: *Self) void {
        scheduler.allocator.destroy(scheduler);
    }

    pub fn add_message(scheduler: *Self, message: *Message, info: types.MessageInfo) void {
        switch (scheduler.scheduler_type) {
            SchedulerType.DeliverAll => scheduler.deliverall_add(message, info),
        }
    }

    pub fn reset(scheduler: *Self) void {
        scheduler.messages.clearRetainingCapacity();
    }

    pub fn tick(scheduler: *Self) !TickResult {
        const result = switch (scheduler.scheduler_type) {
            SchedulerType.DeliverAll => scheduler.deliverall_tick(),
        };
        return result;
    }

    fn deliverall_add(scheduler: *Self, message: *Message, info: types.MessageInfo) void {
        if (scheduler.messages.items.len > scheduler.options.max_intransit_messages) {
            // Dropping message because reached capacity
            return;
        }
        scheduler.messages.appendAssumeCapacity(types.MessageWrapper{
            .message = message,
            .info = info,
        });
    }

    fn deliverall_tick(scheduler: *Self) !TickResult {
        const out = TickResult{
            .to_deliver = try scheduler.messages.toOwnedSlice(),
            .to_drop = null,
        };
        scheduler.messages.clearRetainingCapacity();
        return out;
    }
};
