const std = @import("std");

const B = @import("builtin.zig");
const C = @import("common.zig");
const E = @import("eval.zig");
const P = @import("parse.zig");
const Pre = @import("preproc.zig");
const S = @import("symbol.zig");
const T = @import("tok.zig");

const En = @import("env.zig");
const EnvRef = ValueRef;
const alloc = C.alloc;
const toString = C.toString;
const ValueRef = C.ValueRef;

pub fn main() !void {
    const args = try std.process.argsAlloc(C.alloc);
    const env = try init();
    if (args.len == 2) {
        try evalFile(args[1], env);
        return;
    }
    try repl(env);
}

pub fn init() !EnvRef {
    try S.init();
    try C.init();
    En.init();

    const env = try B.loadBuiltin();
    _, const ret = try eval(@embedFile("builtin.scm"), env);
    return ret;
}

fn evalFile(filepath: []const u8, env: EnvRef) !void {
    var file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [65536]u8 = undefined;
    const size = try in_stream.readAll(&buf);
    _ = try eval(buf[0..size], env);
}

fn repl(env: EnvRef) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var e = env;
    while (true) {
        try stdout.print(">>> ", .{});
        const line = readLine(stdin) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (line) |l| {
            if (l.len == 0) continue;
            const result, e = try eval(l, e);
            try stdout.print("{s}\n", .{try toString(result)});
        }
    }
}

fn readLine(reader: anytype) !?[]const u8 {
    // Don't free buffer since it's referenced from slices in env entry.
    const len = 8192;
    const buffer: []u8 = try alloc.alloc(u8, len);
    var fbs = std.io.fixedBufferStream(buffer);
    try reader.streamUntilDelimiter(fbs.writer(), '\n', len);
    return fbs.getWritten();
}

pub fn eval(code: []const u8, env: EnvRef) !struct { ValueRef, EnvRef } {
    const sexprs = try toAST(code);
    var ret = C.empty();
    var new_env = env;
    for (sexprs) |expr| ret, new_env = try E.evaluate(expr, new_env);
    return .{ ret, new_env };
}

pub fn toAST(code: []const u8) ![]ValueRef {
    const tokens = try T.tokenize(code);
    const sexprs = try P.parse(tokens);
    const result = try C.alloc.alloc(ValueRef, sexprs.len);
    try Pre.preprocessAll(sexprs, result);
    return result;
}
