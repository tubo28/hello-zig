const std = @import("std");

const S = @import("symbol.zig");

const SymbolID = S.ID;
const Env = @import("env.zig").Env;
const EnvRef = Env.Ref;

pub const ValueRef = *const Value;
pub const EvalResult = struct { ValueRef, EnvRef };

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const alloc = gpa.allocator();

pub const Cons = struct {
    car: ValueRef,
    cdr: ValueRef,
};

pub fn new(ty: anytype, x: ty) !*ty {
    var ret: *ty = try alloc.create(ty);
    ret.* = x;
    return ret;
}

pub const ValueTag = enum { number, symbol, binding, cons, lambda, macro, b_func, b_spf };
/// Node of tree.
/// It is a branch only if cons, otherwise leaf.
pub const Value = union(ValueTag) {
    number: i64,
    symbol: SymbolID,
    binding: *Binding,
    cons: *const Cons,
    lambda: *const Lambda,
    macro: *const Macro,
    b_func: usize, // Index of table
    b_spf: usize,
};

const Binding = struct {
    symbol: SymbolID,
    ref: ValueRef,
};

pub fn newCons(car: ValueRef, cdr: ValueRef) !ValueRef {
    return new(
        Value,
        Value{ .cons = try new(Cons, Cons{ .car = car, .cdr = cdr }) },
    );
}

pub const Lambda = struct {
    params: []SymbolID,
    body: ValueRef,
    env: EnvRef, // captured env (lexical scope)
    // TODO: Add table for function argument to make beta reduction faster
};

/// empty is a ConsCell such that both its car and cdr are itself.
pub fn empty() ValueRef {
    return empty_opt.?;
}

pub fn init() !void {
    var e = try alloc.create(Value);
    empty_cons_opt = try new(Cons, Cons{ .car = e, .cdr = e });
    e.* = Value{ .cons = empty_cons_opt.? };
    empty_opt = e;

    try initSpecialSymbol("#t", &t_opt);
    try initSpecialSymbol("#f", &f_opt);
}

fn initSpecialSymbol(sym: []const u8, dst: *?*Value) !void {
    var ptr = try alloc.create(Value);
    ptr.* = Value{ .symbol = try S.getOrRegister(sym) };
    dst.* = ptr;
}

fn emptyCons() *const Cons {
    _ = empty();
    return empty_cons_opt.?;
}

// var quote_opt: ?*Value = null;
var f_opt: ?*Value = null;
var t_opt: ?*Value = null;

var empty_opt: ?*Value = null;
var empty_cons_opt: ?*Cons = null;

// pub fn quote() ValueRef {
//     return quote_opt.?;
// }

/// #f.
/// The only falsy value.
pub fn f() ValueRef {
    return f_opt.?;
}

/// #t.
/// #t is just a non-special symbol in Scheme but useful to implement interpreter.
pub fn t() ValueRef {
    return t_opt.?;
}

/// Convert sequence of cons cell like (foo bar buz) to ArrayListUnmanaged(ValueRef).
pub fn toArrayListUnmanaged(cons_list: ValueRef, buf: []ValueRef) std.ArrayListUnmanaged(ValueRef) {
    var list = std.ArrayListUnmanaged(ValueRef).fromOwnedSlice(buf);
    list.items.len = 0;
    var h = cons_list;
    while (h != empty()) {
        std.debug.assert(h.* == .cons); // is cons?
        std.debug.assert(list.items.len < buf.len);
        list.appendAssumeCapacity(h.cons.car);
        h = _cdr(h);
    }
    return list;
}

pub fn toConsList(list: []ValueRef) !ValueRef {
    if (list.len == 0) return empty();
    return try newCons(list[0], try toConsList(list[1..]));
}

/// The "deep equal" function for values.
pub fn deepEql(x: ValueRef, y: ValueRef) bool {
    if (x == empty() or y == empty()) return x == y;
    if (@as(ValueTag, x.*) != @as(ValueTag, y.*)) return false;
    switch (x.*) {
        Value.number => |x_| return x_ == y.number,
        Value.symbol => |x_| return x_ == y.symbol,
        Value.binding => |x_| return deepEql(x_.ref, y.binding.ref),
        Value.b_func => |x_| return x_ == y.b_func,
        Value.b_spf => |x_| return x_ == y.b_spf,
        Value.cons => |x_| return deepEql(x_.car, y.cons.car) and deepEql(x_.cdr, y.cons.cdr),
        Value.macro => |x_| return x_.name == y.macro.name,
        Value.lambda => unreachable,
    }
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
        Value.symbol => |sym| try builder.appendSlice(S.getName(sym).?),
        Value.binding => |b| try builder.appendSlice(S.getName(b.symbol).?),
        Value.lambda => try builder.appendSlice("<lambda>"),
        Value.macro => |macro| {
            try builder.appendSlice("<macro:");
            try builder.appendSlice(S.getName(macro.name).?);
            try builder.appendSlice(">");
        },
        Value.b_func => try builder.appendSlice("<builtin function>"),
        Value.b_spf => try builder.appendSlice("<builtin special form>"),
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

// pub fn panicAt(tok: T, message: []const u8) void {
//     const stderr = std.io.getStdErr().writer();
//     nosuspend {
//         stderr.print("error: {s}\n", .{message});
//         stderr.print("error: {s}\n", .{message});
//         for (0..tok.index + 7) |_| stderr.print(" ", .{});
//         stderr.print("^\n");
//     }
//     unreachable;
// }

pub fn _car(x: ValueRef) ValueRef {
    return x.cons.car;
}

pub fn _cdr(x: ValueRef) ValueRef {
    return x.cons.cdr;
}

pub fn _cddr(x: ValueRef) ValueRef {
    return _cdr(x).cons.cdr;
}

pub fn _cadr(x: ValueRef) ValueRef {
    return _cdr(x).cons.car;
}

pub const Macro = struct {
    name: S.ID,
    rules: []MacroRule,
};

pub const MacroRule = struct {
    pattern: ValueRef, // Consists only of cons or symbol
    template: ValueRef,
};
