const std = @import("std");

pub const Token = @import("tokenize.zig").Token;
pub const ValueRef = *const Value;

const Symbol = @import("symbol.zig");
const SymbolID = Symbol.ID;

pub const Map = std.AutoHashMap(SymbolID, ValueRef); // TODO: Dependency for env
pub const EvalResult = struct { ValueRef, Map };

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
    symbol: SymbolID,
    cons: *const Cons,
    function: *const Function,
    b_function: usize, // Index of table
    b_special_form: usize,
};

pub fn newBFunctionValue(i: usize) !ValueRef {
    var ret = try alloc.create(Value);
    ret.* = Value{ .b_function = i };
    return ret;
}

pub fn newBSpecialForm(i: usize) !ValueRef {
    var ret = try alloc.create(Value);
    ret.* = Value{ .b_special_form = i };
    return ret;
}

pub fn newConsValue(car: ValueRef, cdr: ValueRef) !ValueRef {
    var ret = try alloc.create(Value);
    ret.* = Value{ .cons = try newCons(car, cdr) };
    return ret;
}

pub fn newNumberValue(x: i64) !ValueRef {
    var ret = try alloc.create(Value);
    ret.* = Value{ .number = x };
    return ret;
}

pub fn newSymbolValue(x: SymbolID) !ValueRef {
    var ret = try alloc.create(Value);
    ret.* = Value{ .symbol = x };
    return ret;
}

pub const Function = struct {
    name: ?SymbolID, // null for lambda
    params: []SymbolID,
    body: []ValueRef,
    env: Map, // captured env (lexical scope)
};

pub fn newFunctionValue(func: *const Function) !ValueRef {
    var ret = try alloc.create(Value);
    ret.* = Value{ .function = func };
    return ret;
}

pub fn newFunction(name: ?SymbolID, params: []SymbolID, body: []ValueRef, env: Map) !*Function {
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

fn emptyCons() *const Cons {
    _ = empty();
    return empty_cons_opt.?;
}

pub fn f() ValueRef {
    if (f_opt) |ff| return ff;
    var f_ = alloc.create(Value) catch @panic("failed to alloc #f");
    f_.* = Value{ .symbol = Symbol.getOrRegister("#f") catch unreachable };
    f_opt = f_;
    return f_opt.?;
}

// #t.
// #t is just a non-special symbol in Scheme but useful to implement interpreter.
pub fn t() ValueRef {
    if (t_opt) |tt| return tt;
    var t_ = alloc.create(Value) catch @panic("failed to alloc #t");
    t_.* = Value{ .symbol = Symbol.getOrRegister("#t") catch @panic("symbol #t not registered") };
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
    if (cell == empty()) {
        try builder.appendSlice("()");
        return;
    }
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
        Value.symbol => |sym| try builder.appendSlice(Symbol.getName(sym).?),
        Value.function => |func| {
            if (func.name) |n| {
                try builder.appendSlice("<function:");
                try builder.appendSlice(Symbol.getName(n).?);
                try builder.appendSlice(">");
            } else {
                try builder.appendSlice("<lambda>");
            }
        },
        Value.b_function => try builder.appendSlice("<builtin function>"),
        Value.b_special_form => try builder.appendSlice("<builtin special form>"),
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
