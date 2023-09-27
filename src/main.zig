const std = @import("std");

const V = common.ValueRef;
const Map = common.Map;

const common = @import("common.zig");
const nil = common.nil;
const toString = common.toString;
const alloc = common.alloc;
const Value = common.Value;

const T = @import("tokenize.zig");
const P = @import("parse.zig");
const E = @import("evaluate.zig");

pub fn main() !void {
    const args = try std.process.argsAlloc(common.alloc);
    if (args.len == 2) {
        try evalFile(args[1]);
        return;
    }
    try repl();
}

fn evalFile(filepath: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    var file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [65536]u8 = undefined;
    const size = try in_stream.readAll(&buf);
    var env = Map.init(common.alloc);
    const result, _ = try eval(buf[0..size], env);
    try stdout.print("{s}\n", .{try toString(result)});
}

fn repl() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var env = Map.init(alloc);
    while (true) {
        try stdout.print(">>> ", .{});
        const line = readLine(stdin) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (line) |l| {
            if (l.len == 0) continue;
            const result, env = try eval(l, env);
            try stdout.print("{s}\n", .{try toString(result)});
        }
    }
}

fn readLine(reader: anytype) !?[]const u8 {
    // Don't free buffer since it's referenced from slices in env entry.
    const len = 8192;
    var buffer: []u8 = try alloc.alloc(u8, len);
    var fbs = std.io.fixedBufferStream(buffer);
    try reader.streamUntilDelimiter(fbs.writer(), '\n', len);
    return fbs.getWritten();
}

fn eval(code: []const u8, env: Map) !struct { V, Map } {
    const tokens = try T.tokenize(code);
    const sexprs = try P.parse(tokens);
    var ret = nil();
    var new_env = try env.clone();
    for (sexprs) |expr| ret, new_env = try E.evaluate(expr, new_env);
    // std.log.debug("eval result: {s}", .{tos(ret)});
    return .{ ret, new_env };
}

fn parse(code: []const u8) ![]V {
    const tokens = try T.tokenize(code);
    const sexprs = try P.parse(tokens);
    // for (sexprs) |expr| {
    //     std.log.debug("parse result: {s}", .{tos(expr)});
    // }
    return sexprs;
}

test "tokenize" {
    const TestCase = struct {
        code: []const u8,
        want: []V,
    };

    const cases = [_]TestCase{
        TestCase{
            .code = "(+ 1 2)",
            .want = try parse("3"),
        },
        TestCase{
            .code = "(+ 1 2 (+ 3 4) (+ 5 (+ 6 7)) 8 9 10)",
            .want = try parse("55"),
        },
        TestCase{
            .code = "'(1 2 3)",
            .want = try parse("(1 2 3)"),
        },
        TestCase{
            .code = "(length '(1 2 3))",
            .want = try parse("3"),
        },
        TestCase{
            .code = "(+ (length '(a b c)) (length '(d e)))",
            .want = try parse("5"),
        },
        TestCase{
            .code = "(print hello)",
            .want = try parse("hello"),
        },
        TestCase{
            .code = "(progn (print hello) (print world) (+ (length '(a b c)) (length '(d e))))",
            .want = try parse("5"),
        },
        TestCase{
            .code = "(setq menu '(tea coffee milk))",
            .want = try parse("(tea coffee milk)"),
        },
        TestCase{
            .code = "(setq a 1) (+ a a)",
            .want = try parse("2"),
        },
        TestCase{
            .code = "(progn (setq a 1) (setq b 2) (+ a b 3))",
            .want = try parse("6"),
        },
        TestCase{
            .code = "(progn (setq p '(3 1 4 1 5)) (print (length p)))",
            .want = try parse("5"),
        },
        TestCase{
            .code = "(car '(a b c))",
            .want = try parse("a"),
        },
        TestCase{
            .code = "(car '((a b) (c d)))",
            .want = try parse("(a b)"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (car menu))",
            .want = try parse("tea"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (cdr menu))",
            .want = try parse("(coffee milk)"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (cdr (cdr menu)))",
            .want = try parse("(milk)"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (cdr (cdr (cdr menu))))",
            .want = try parse("nil"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (car (cdr menu)))",
            .want = try parse("coffee"),
        },
        TestCase{
            .code = "(cons '(a b) '(c d))",
            .want = try parse("((a b) c d)"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (cons 'cocoa menu))",
            .want = try parse("(cocoa tea coffee milk)"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (cons 'cocoa (cdr menu)))",
            .want = try parse("(cocoa coffee milk)"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (car (cdr (cdr menu))))",
            .want = try parse("milk"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (cons 'juice (cdr menu)))",
            .want = try parse("(juice coffee milk)"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (cons (car menu) (cons 'juice (cdr menu))))",
            .want = try parse("(tea juice coffee milk)"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (cons (car menu) (cdr (cdr menu))))",
            .want = try parse("(tea milk)"),
        },
        TestCase{
            .code = "(progn (setq menu '(tea coffee milk)) (cons (car (cdr menu)) (cons (car menu) (cdr (cdr menu)))))",
            .want = try parse("(coffee tea milk)"),
        },
        TestCase{
            .code = "(progn (defun double (x) (+ x x)) (double 1))",
            .want = try parse("2"),
        },
        TestCase{
            .code = "(progn (defun double (x) (+ x x)) (double (double 1)))",
            .want = try parse("4"),
        },
        TestCase{
            .code = "(progn (defun double (x) (+ x x)) (double (double 1)))",
            .want = try parse("4"),
        },
        TestCase{
            .code = "(if t 'true 'false)",
            .want = try parse("true"),
        },
        TestCase{
            .code = "(if 0 'true 'false)",
            .want = try parse("true"),
        },
        TestCase{
            .code = "(if nil 'true 'false)",
            .want = try parse("false"),
        },
        TestCase{
            .code = "(if () 'true 'false)",
            .want = try parse("false"),
        },
        TestCase{
            .code = "(if t 'true)",
            .want = try parse("true"),
        },
        TestCase{
            .code = "(if nil 'true)",
            .want = try parse("nil"),
        },
        TestCase{
            .code = @embedFile("examples/fibonacci.lisp"),
            .want = try parse("89"),
        },
        TestCase{
            .code = "(let ((x 1) (y 2)) (+ 1 2))",
            .want = try parse("3"),
        },
        TestCase{
            .code = "(cond ((= 0 1) 'foo) ((= 0 0) 'bar))",
            .want = try parse("bar"),
        },
        TestCase{
            .code = "(cond ((= 0 1) 'foo) (t 'bar))",
            .want = try parse("bar"),
        },
        TestCase{
            .code = "(cond ((= 0 1) 'foo) ((= 0 2) 'bar))",
            .want = try parse("nil"),
        },
        TestCase{
            .code = @embedFile("examples/mergesort.lisp"),
            .want = try parse("(1 1 2 3 3 4 5 5 5 6 7 8 9 9 9)"),
        },
        TestCase{
            .code = @embedFile("examples/tarai.lisp"),
            .want = try parse("8"),
        },
        TestCase{
            .code = "(let ((f (lambda (x) (+ x x)))) (f 1))",
            .want = try parse("2"),
        },
    };

    std.testing.log_level = std.log.Level.debug;
    for (cases, 1..) |c, i| {
        const code = c.code;
        std.log.debug("test {}: {s}", .{ i, code });
        const get, _ = try eval(code, Map.init(alloc));
        try std.testing.expect(E.deepEql(get, c.want[c.want.len - 1]));
        std.log.info("test result: ok", .{});
    }
}
