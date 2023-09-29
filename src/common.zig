const std = @import("std");

pub const Token = @import("tokenize.zig").Token;
pub const ValueRef = *const Value;

pub const Map = std.StringHashMap(ValueRef); // TODO: Dependency for env

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const alloc = gpa.allocator();

pub const Cons = struct {
    car: ValueRef,
    cdr: ValueRef,
};

pub fn newCons(car: ValueRef, cdr: ValueRef) !*Cons {
    var cons: *Cons = try alloc.create(Cons);
    cons.* = Cons{ .car = car, .cdr = cdr };
    return cons;
}

/// Node of tree.
/// It is a branch only if cons, otherwise leaf.
pub const Value = union(enum) {
    number: i64,
    symbol: []const u8,
    cons: *const Cons,
    function: *const Function,
};

pub fn newConsValue(car: ValueRef, cdr: ValueRef) !ValueRef {
    var ret = try alloc.create(Value);
    ret.* = Value{ .cons = try newCons(car, cdr) };
    return ret;
}

pub fn newNumberValue(x: i64) !ValueRef {
    return newAtomValue(i64, x);
}

pub fn newSymbolValue(x: []const u8) !ValueRef {
    return try newAtomValue([]const u8, x);
}

fn newAtomValue(comptime T: type, value: T) !ValueRef {
    var ret = try alloc.create(Value);
    switch (T) {
        i64 => ret.* = Value{ .number = value },
        []const u8 => ret.* = Value{ .symbol = value },
        else => @panic("currently atom of only i64 or string are implemented"),
    }
    return ret;
}

pub const Function = struct {
    name: ?[]const u8, // null for lambda
    params: [][]const u8,
    body: []ValueRef,
    env: Map, // captured env (lexical scope)
};

pub fn newFunctionValue(
    name: ?[]const u8,
    params: [][]const u8,
    body: []ValueRef,
    env: Map,
) !ValueRef {
    var ret = try alloc.create(Value);
    ret.* = Value{ .function = try newFunc(name, params, body, env) };
    return ret;
}

pub fn newFunc(name: ?[]const u8, params: [][]const u8, body: []ValueRef, env: Map) !*Function {
    var ret: *Function = try alloc.create(Function);
    ret.* = Function{
        .name = name,
        .params = params,
        .body = body,
        .env = env,
    };
    return ret;
}

var empty_opt: ?*Value = null;
var empty_cons_opt: ?*Cons = null;
var t_opt: ?*Value = null;
var f_opt: ?*Value = null;

/// empty is a ConsCell such that both its car and cdr are itself.
pub fn empty() ValueRef {
    if (empty_opt) |e| return e;
    var e = alloc.create(Value) catch @panic("failed to alloc nil");
    empty_cons_opt = newCons(e, e) catch unreachable;
    e.* = Value{ .cons = empty_cons_opt.? };
    empty_opt = e;
    return empty_opt.?;
}

fn emptyCons() ValueRef {
    _ = empty();
    return empty_cons_opt.?;
}

pub fn f() ValueRef {
    if (f_opt) |ff| return ff;
    var f_ = alloc.create(Value) catch @panic("failed to alloc #f");
    f_.* = Value{ .symbol = "#f" };
    f_opt = f_;
    return f_opt.?;
}

// #t.
// #t is just a non-special symbol in Scheme but useful to implement interpreter.
pub fn t() ValueRef {
    if (t_opt) |tt| return tt;
    var t_ = alloc.create(Value) catch @panic("failed to alloc #t");
    t_.* = Value{ .symbol = "#t" };
    t_opt = t_;
    return t_opt.?;
}

pub fn toString(cell: ValueRef) ![]const u8 {
    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    try toStringInner(cell, &buf);
    return try buf.toOwnedSlice();
}

fn toStringInner(cell: ValueRef, builder: *std.ArrayList(u8)) anyerror!void {
    switch (cell.*) {
        Value.cons => |c| {
            try builder.append('(');
            try consToString(c, builder);
            try builder.append(')');
        },
        Value.number => |num| {
            var buffer: [30]u8 = undefined;
            const str = std.fmt.bufPrint(
                buffer[0..],
                "{}",
                .{num},
            ) catch @panic("too large integer");
            try builder.appendSlice(str);
        },
        Value.symbol => |sym| try builder.appendSlice(sym),
        Value.function => |func| {
            if (func.name) |n| {
                try builder.appendSlice("<function:");
                try builder.appendSlice(n);
                try builder.appendSlice(">");
            } else {
                try builder.appendSlice("<lambda>");
            }
        },
    }
}

fn consToString(x: *const Cons, builder: *std.ArrayList(u8)) !void {
    switch (x.cdr.*) {
        Value.cons => |next| {
            // List
            try toStringInner(x.car, builder);
            if (next == emptyCons()) return;
            try builder.append(' ');
            try consToString(next, builder);
        },
        else => {
            // Dotted pair
            try toStringInner(x.car, builder);
            try builder.appendSlice(" . ");
            try toStringInner(x.cdr, builder);
        },
    }
}

pub fn panicAt(tok: Token, message: []const u8) void {
    const stderr = std.io.getStdErr().writer();
    nosuspend {
        stderr.print("error: {s}\n", .{message});
        stderr.print("error: {s}\n", .{message});
        for (0..tok.index + 7) |_| stderr.print(" ", .{});
        stderr.print("^\n");
    }
    unreachable;
}
