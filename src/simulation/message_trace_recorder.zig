const std = @import("std");
const log = std.log.scoped(.message_trace_recorder);
const Path = @import("network_simulator.zig").Path;
const MessagePool = @import("../message_pool.zig").MessagePool;
const Message = MessagePool.Message;
const vsr = @import("../vsr.zig");

pub const TraceElement = struct {
    view: u32,
    command: vsr.Command,
    path: Path,
};

pub const MessageTraceRecorder = struct {
    file_path: []const u8,
    trace: std.ArrayList(TraceElement),

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !MessageTraceRecorder {
        return MessageTraceRecorder{
            .file_path = file_path,
            .trace = std.ArrayList(TraceElement).init(allocator),
        };
    }

    pub fn deinit(self: *MessageTraceRecorder) void {
        self.trace.deinit();
    }

    pub fn send(self: *MessageTraceRecorder, message: *Message, path: Path) void {
        self.trace.append(TraceElement{ .view = message.header.view, .command = message.header.command, .path = path }) catch {};
    }

    pub fn receive(self: *MessageTraceRecorder, message: *Message, path: Path) void {
        self.trace.append(TraceElement{ .view = message.header.view, .command = message.header.command, .path = path }) catch {};
    }

    pub fn record_trace(self: *MessageTraceRecorder) !void {
        var file = try std.fs.cwd().createFile(self.file_path, .{});
        defer file.close();
        log.info("Writing trace to {s}", .{self.file_path});
        try std.json.stringify(self.trace.items, .{}, file.writer());
    }
};

pub fn send_handler(context: ?*anyopaque, packet: *Message, path: Path) void {
    const trace_recorder: *MessageTraceRecorder = @ptrCast(@alignCast(context.?));
    trace_recorder.send(packet, path);
}

pub fn receive_handler(context: ?*anyopaque, packet: *Message, path: Path) void {
    const trace_recorder: *MessageTraceRecorder = @ptrCast(@alignCast(context.?));
    trace_recorder.receive(packet, path);
}
