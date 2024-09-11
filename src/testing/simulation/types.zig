const std = @import("std");
const vsr = @import("../../vsr.zig");
const ProcessType = vsr.ProcessType;
const MessagePool = @import("../../message_pool.zig").MessagePool;
const Message = MessagePool.Message;

pub const Process = union(ProcessType) {
    replica: u8,
    client: u128,
};

pub const MessageInfo = struct {
    source: Process,
    target: Process,
};

pub const MessageWrapper = struct {
    info: MessageInfo,
    message: *Message,
};
