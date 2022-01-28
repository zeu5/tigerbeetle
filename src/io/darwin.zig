const std = @import("std");
const os = std.os;
const mem = std.mem;
const assert = std.debug.assert;

const FIFO = @import("../fifo.zig").FIFO;
const Time = @import("../time.zig").Time;
const buffer_limit = @import("../io.zig").buffer_limit;

pub const IO = struct {
    kq: os.fd_t,
    time: Time = .{},
    io_inflight: usize = 0,
    timeouts: FIFO(Completion) = .{},
    completed: FIFO(Completion) = .{},
    io_pending: FIFO(Completion) = .{},

    pub fn init(entries: u12, flags: u32) !IO {
        _ = entries;
        _ = flags;

        const kq = try os.kqueue();
        assert(kq > -1);
        return IO{ .kq = kq };
    }

    pub fn deinit(self: *IO) void {
        assert(self.kq > -1);
        os.close(self.kq);
        self.kq = -1;
    }

    /// Pass all queued submissions to the kernel and peek for completions.
    pub fn tick(self: *IO) !void {
        return self.flush(false);
    }

    /// Pass all queued submissions to the kernel and run for `nanoseconds`.
    /// The `nanoseconds` argument is a u63 to allow coercion to the i64 used
    /// in the __kernel_timespec struct.
    pub fn run_for_ns(self: *IO, nanoseconds: u63) !void {
        var timed_out = false;
        var completion: Completion = undefined;
        const on_timeout = struct {
            fn callback(
                timed_out_ptr: *bool,
                _completion: *Completion,
                result: TimeoutError!void,
            ) void {
                _ = _completion;
                _ = result catch unreachable;

                timed_out_ptr.* = true;
            }
        }.callback;

        // Submit a timeout which sets the timed_out value to true to terminate the loop below.
        self.timeout(
            *bool,
            &timed_out,
            on_timeout,
            &completion,
            nanoseconds,
        );

        // Loop until our timeout completion is processed above, which sets timed_out to true.
        // LLVM shouldn't be able to cache timed_out's value here since its address escapes above.
        while (!timed_out) {
            try self.flush(true);
        }
    }

    fn flush(self: *IO, wait_for_completions: bool) !void {
        var io_pending = self.io_pending.peek();
        var events: [256]os.Kevent = undefined;

        // Check timeouts and fill events with completions in io_pending
        // (they will be submitted through kevent).
        // Timeouts are expired here and possibly pushed to the completed queue.
        const next_timeout = self.flush_timeouts();
        const change_events = self.flush_io(&events, &io_pending);

        // Only call kevent() if we need to submit io events or if we need to wait for completions.
        if (change_events > 0 or self.completed.peek() == null) {
            // Zero timeouts for kevent() implies a non-blocking poll
            var ts = std.mem.zeroes(os.timespec);

            // We need to wait (not poll) on kevent if there's nothing to submit or complete.
            // We should never wait indefinitely (timeout_ptr = null for kevent) given:
            // - tick() is non-blocking (wait_for_completions = false)
            // - run_for_ns() always submits a timeout
            if (change_events == 0 and self.completed.peek() == null) {
                if (wait_for_completions) {
                    const timeout_ns = next_timeout orelse @panic("kevent() blocking forever");
                    ts.tv_nsec = @intCast(@TypeOf(ts.tv_nsec), timeout_ns % std.time.ns_per_s);
                    ts.tv_sec = @intCast(@TypeOf(ts.tv_sec), timeout_ns / std.time.ns_per_s);
                } else if (self.io_inflight == 0) {
                    return;
                }
            }

            const new_events = try os.kevent(
                self.kq,
                events[0..change_events],
                events[0..events.len],
                &ts,
            );

            // Mark the io events submitted only after kevent() successfully processed them
            self.io_pending.out = io_pending;
            if (io_pending == null) {
                self.io_pending.in = null;
            }

            self.io_inflight += change_events;
            self.io_inflight -= new_events;

            for (events[0..new_events]) |event| {
                const completion = @intToPtr(*Completion, event.udata);
                completion.next = null;
                self.completed.push(completion);
            }
        }

        var completed = self.completed;
        self.completed = .{};
        while (completed.pop()) |completion| {
            (completion.callback)(self, completion);
        }
    }

    fn flush_io(_: *IO, events: []os.Kevent, io_pending_top: *?*Completion) usize {
        for (events) |*event, flushed| {
            const completion = io_pending_top.* orelse return flushed;
            io_pending_top.* = completion.next;

            const event_info = switch (completion.operation) {
                .accept => |op| [2]c_int{ op.socket, os.system.EVFILT_READ },
                .connect => |op| [2]c_int{ op.socket, os.system.EVFILT_WRITE },
                .read => |op| [2]c_int{ op.fd, os.system.EVFILT_READ },
                .write => |op| [2]c_int{ op.fd, os.system.EVFILT_WRITE },
                .recv => |op| [2]c_int{ op.socket, os.system.EVFILT_READ },
                .send => |op| [2]c_int{ op.socket, os.system.EVFILT_WRITE },
                else => @panic("invalid completion operation queued for io"),
            };

            event.* = .{
                .ident = @intCast(u32, event_info[0]),
                .filter = @intCast(i16, event_info[1]),
                .flags = os.system.EV_ADD | os.system.EV_ENABLE | os.system.EV_ONESHOT,
                .fflags = 0,
                .data = 0,
                .udata = @ptrToInt(completion),
            };
        }
        return events.len;
    }

    fn flush_timeouts(self: *IO) ?u64 {
        var min_timeout: ?u64 = null;
        var timeouts: ?*Completion = self.timeouts.peek();
        while (timeouts) |completion| {
            timeouts = completion.next;

            // NOTE: We could cache `now` above the loop but monotonic() should be cheap to call.
            const now = self.time.monotonic();
            const expires = completion.operation.timeout.expires;

            // NOTE: remove() could be O(1) here with a doubly-linked-list
            // since we know the previous Completion.
            if (now >= expires) {
                self.timeouts.remove(completion);
                self.completed.push(completion);
                continue;
            }

            const timeout_ns = expires - now;
            if (min_timeout) |min_ns| {
                min_timeout = std.math.min(min_ns, timeout_ns);
            } else {
                min_timeout = timeout_ns;
            }
        }
        return min_timeout;
    }

    /// This struct holds the data needed for a single IO operation
    pub const Completion = struct {
        next: ?*Completion,
        context: ?*anyopaque,
        callback: fn (*IO, *Completion) void,
        operation: Operation,
    };

    const Operation = union(enum) {
        accept: struct {
            socket: os.socket_t,
        },
        close: struct {
            fd: os.fd_t,
        },
        connect: struct {
            socket: os.socket_t,
            address: std.net.Address,
            initiated: bool,
        },
        fsync: struct {
            fd: os.fd_t,
        },
        read: struct {
            fd: os.fd_t,
            buf: [*]u8,
            len: u32,
            offset: u64,
        },
        recv: struct {
            socket: os.socket_t,
            buf: [*]u8,
            len: u32,
        },
        send: struct {
            socket: os.socket_t,
            buf: [*]const u8,
            len: u32,
        },
        timeout: struct {
            expires: u64,
        },
        write: struct {
            fd: os.fd_t,
            buf: [*]const u8,
            len: u32,
            offset: u64,
        },
    };

    fn submit(
        self: *IO,
        context: anytype,
        comptime callback: anytype,
        completion: *Completion,
        comptime operation_tag: std.meta.Tag(Operation),
        operation_data: anytype,
        comptime OperationImpl: type,
    ) void {
        const Context = @TypeOf(context);
        const onCompleteFn = struct {
            fn onComplete(io: *IO, _completion: *Completion) void {
                // Perform the actual operaton
                const op_data = &@field(_completion.operation, @tagName(operation_tag));
                const result = OperationImpl.doOperation(op_data);

                // Requeue onto io_pending if error.WouldBlock
                switch (operation_tag) {
                    .accept, .connect, .read, .write, .send, .recv => {
                        _ = result catch |err| switch (err) {
                            error.WouldBlock => {
                                _completion.next = null;
                                io.io_pending.push(_completion);
                                return;
                            },
                            else => {},
                        };
                    },
                    else => {},
                }

                // Complete the Completion
                return callback(
                    @intToPtr(Context, @ptrToInt(_completion.context)),
                    _completion,
                    result,
                );
            }
        }.onComplete;

        completion.* = .{
            .next = null,
            .context = context,
            .callback = onCompleteFn,
            .operation = @unionInit(Operation, @tagName(operation_tag), operation_data),
        };

        switch (operation_tag) {
            .timeout => self.timeouts.push(completion),
            else => self.completed.push(completion),
        }
    }

    pub const AcceptError = os.AcceptError || os.SetSockOptError;

    pub fn accept(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: AcceptError!os.socket_t,
        ) void,
        completion: *Completion,
        socket: os.socket_t,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .accept,
            .{
                .socket = socket,
            },
            struct {
                fn doOperation(op: anytype) AcceptError!os.socket_t {
                    const fd = try os.accept(
                        op.socket,
                        null,
                        null,
                        os.SOCK.NONBLOCK | os.SOCK.CLOEXEC,
                    );
                    errdefer os.close(fd);

                    // Darwin doesn't support os.MSG_NOSIGNAL to avoid getting SIGPIPE on socket send().
                    // Instead, it uses the SO_NOSIGPIPE socket option which does the same for all send()s.
                    os.setsockopt(
                        fd,
                        os.SOL.SOCKET,
                        os.SO.NOSIGPIPE,
                        &mem.toBytes(@as(c_int, 1)),
                    ) catch |err| return switch (err) {
                        error.TimeoutTooBig => unreachable,
                        error.PermissionDenied => error.NetworkSubsystemFailed,
                        error.AlreadyConnected => error.NetworkSubsystemFailed,
                        error.InvalidProtocolOption => error.ProtocolFailure,
                        else => |e| e,
                    };

                    return fd;
                }
            },
        );
    }

    pub const CloseError = error{
        FileDescriptorInvalid,
        DiskQuota,
        InputOutput,
        NoSpaceLeft,
    } || os.UnexpectedError;

    pub fn close(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: CloseError!void,
        ) void,
        completion: *Completion,
        fd: os.fd_t,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .close,
            .{
                .fd = fd,
            },
            struct {
                fn doOperation(op: anytype) CloseError!void {
                    return switch (os.errno(os.system.close(op.fd))) {
                        os.E.SUCCESS => {},
                        os.E.BADF => error.FileDescriptorInvalid,
                        os.E.INTR => {}, // A success, see https://github.com/ziglang/zig/issues/2425
                        os.E.IO => error.InputOutput,
                        else => |errno| os.unexpectedErrno(errno),
                    };
                }
            },
        );
    }

    pub const ConnectError = os.ConnectError;

    pub fn connect(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: ConnectError!void,
        ) void,
        completion: *Completion,
        socket: os.socket_t,
        address: std.net.Address,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .connect,
            .{
                .socket = socket,
                .address = address,
                .initiated = false,
            },
            struct {
                fn doOperation(op: anytype) ConnectError!void {
                    // Don't call connect after being rescheduled by io_pending as it gives EISCONN.
                    // Instead, check the socket error to see if has been connected successfully.
                    const result = switch (op.initiated) {
                        true => os.getsockoptError(op.socket),
                        else => os.connect(op.socket, &op.address.any, op.address.getOsSockLen()),
                    };

                    op.initiated = true;
                    return result;
                }
            },
        );
    }

    pub const FsyncError = os.SyncError;

    pub fn fsync(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: FsyncError!void,
        ) void,
        completion: *Completion,
        fd: os.fd_t,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .fsync,
            .{
                .fd = fd,
            },
            struct {
                fn doOperation(op: anytype) FsyncError!void {
                    _ = os.fcntl(op.fd, os.F.FULLFSYNC, 1) catch return os.fsync(op.fd);
                }
            },
        );
    }

    pub const ReadError = error{
        WouldBlock,
        NotOpenForReading,
        ConnectionResetByPeer,
        Alignment,
        InputOutput,
        IsDir,
        SystemResources,
        Unseekable,
    } || os.UnexpectedError;

    pub fn read(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: ReadError!usize,
        ) void,
        completion: *Completion,
        fd: os.fd_t,
        buffer: []u8,
        offset: u64,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .read,
            .{
                .fd = fd,
                .buf = buffer.ptr,
                .len = @intCast(u32, buffer_limit(buffer.len)),
                .offset = offset,
            },
            struct {
                fn doOperation(op: anytype) ReadError!usize {
                    while (true) {
                        const rc = os.system.pread(
                            op.fd,
                            op.buf,
                            op.len,
                            @bitCast(isize, op.offset),
                        );
                        return switch (os.errno(rc)) {
                            os.E.SUCCESS => @intCast(usize, rc),
                            os.E.INTR => continue,
                            os.E.AGAIN => error.WouldBlock,
                            os.E.BADF => error.NotOpenForReading,
                            os.E.CONNRESET => error.ConnectionResetByPeer,
                            os.E.FAULT => unreachable,
                            os.E.INVAL => error.Alignment,
                            os.E.IO => error.InputOutput,
                            os.E.ISDIR => error.IsDir,
                            os.E.NOBUFS => error.SystemResources,
                            os.E.NOMEM => error.SystemResources,
                            os.E.NXIO => error.Unseekable,
                            os.E.OVERFLOW => error.Unseekable,
                            os.E.SPIPE => error.Unseekable,
                            else => |err| os.unexpectedErrno(err),
                        };
                    }
                }
            },
        );
    }

    pub const RecvError = os.RecvFromError;

    pub fn recv(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: RecvError!usize,
        ) void,
        completion: *Completion,
        socket: os.socket_t,
        buffer: []u8,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .recv,
            .{
                .socket = socket,
                .buf = buffer.ptr,
                .len = @intCast(u32, buffer_limit(buffer.len)),
            },
            struct {
                fn doOperation(op: anytype) RecvError!usize {
                    return os.recv(op.socket, op.buf[0..op.len], 0);
                }
            },
        );
    }

    pub const SendError = os.SendError;

    pub fn send(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: SendError!usize,
        ) void,
        completion: *Completion,
        socket: os.socket_t,
        buffer: []const u8,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .send,
            .{
                .socket = socket,
                .buf = buffer.ptr,
                .len = @intCast(u32, buffer_limit(buffer.len)),
            },
            struct {
                fn doOperation(op: anytype) SendError!usize {
                    return os.send(op.socket, op.buf[0..op.len], 0);
                }
            },
        );
    }

    pub const TimeoutError = error{Canceled} || os.UnexpectedError;

    pub fn timeout(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: TimeoutError!void,
        ) void,
        completion: *Completion,
        nanoseconds: u63,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .timeout,
            .{
                .expires = self.time.monotonic() + nanoseconds,
            },
            struct {
                fn doOperation(_: anytype) TimeoutError!void {
                    return; // timeouts don't have errors for now
                }
            },
        );
    }

    pub const WriteError = os.PWriteError;

    pub fn write(
        self: *IO,
        comptime Context: type,
        context: Context,
        comptime callback: fn (
            context: Context,
            completion: *Completion,
            result: WriteError!usize,
        ) void,
        completion: *Completion,
        fd: os.fd_t,
        buffer: []const u8,
        offset: u64,
    ) void {
        self.submit(
            context,
            callback,
            completion,
            .write,
            .{
                .fd = fd,
                .buf = buffer.ptr,
                .len = @intCast(u32, buffer_limit(buffer.len)),
                .offset = offset,
            },
            struct {
                fn doOperation(op: anytype) WriteError!usize {
                    return os.pwrite(op.fd, op.buf[0..op.len], op.offset);
                }
            },
        );
    }

    pub fn openSocket(family: u32, sock_type: u32, protocol: u32) !os.socket_t {
        const fd = try os.socket(family, sock_type | os.SOCK.NONBLOCK, protocol);
        errdefer os.close(fd);

        // darwin doesn't support os.MSG_NOSIGNAL, but instead a socket option to avoid SIGPIPE.
        try os.setsockopt(fd, os.SOL.SOCKET, os.SO.NOSIGPIPE, &mem.toBytes(@as(c_int, 1)));
        return fd;
    }
};
