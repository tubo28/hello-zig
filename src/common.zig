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
    std.log.debug("alloc.create {} bytes for {}", .{ @sizeOf(ty), ty });
    var ret: *ty = try alloc.create(ty);
    ret.* = x;
    return ret;
}

pub const ValueTag = enum { number, symbol, cons, lambda, b_func, b_form };
/// Node of tree.
/// It is a branch only if cons, otherwise leaf.
pub const Value = union(ValueTag) {
    number: i64,
    symbol: SymbolID,
    cons: Cons,
    lambda: *const Lambda,
    b_func: usize, // Index of table
    b_form: usize,
};

// Lambda param
pub const LocalVal = struct {
    name: SymbolID,
    nth: usize,
};

pub fn newCons(car: ValueRef, cdr: ValueRef) !ValueRef {
    return new(
        Value,
        Value{ .cons = Cons{ .car = car, .cdr = cdr } },
    );
}

pub const Lambda = struct {
    params: ValueRef, // symbols
    // arity: usize,
    body: ValueRef,
    closure: EnvRef, // captured env (lexical scope)
    // TODO: Add table for function argument to make beta reduction faster
};

/// empty is a ConsCell such that both its car and cdr are itself.
pub fn empty() ValueRef {
    return empty_opt.?;
}

pub fn init() !void {
    var e = try new(Value, Value{ .cons = undefined });
    e.cons = Cons{ .car = e, .cdr = e };
    empty_opt = e;

    try initSpecialSymbol("#t", &t_opt);
    try initSpecialSymbol("#f", &f_opt);
}

fn initSpecialSymbol(sym: []const u8, dst: *?*Value) !void {
    var ptr = try new(Value, Value{ .symbol = try S.getOrRegister(sym) });
    dst.* = ptr;
}

var f_opt: ?*Value = null;
var t_opt: ?*Value = null;
var empty_opt: ?*Value = null;

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
pub fn flattenToALU(cons_list: ValueRef, buf: []ValueRef) std.ArrayListUnmanaged(ValueRef) {
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

pub fn listLength(cons_list: ValueRef) usize {
    std.debug.assert(cons_list.* == .cons);
    if (cons_list == empty()) return 0;
    return 1 + listLength(_cdr(cons_list));
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
        Value.b_func => |x_| return x_ == y.b_func,
        Value.b_form => |x_| return x_ == y.b_form,
        Value.cons => |x_| return deepEql(x_.car, y.cons.car) and deepEql(x_.cdr, y.cons.cdr),
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
        Value.lambda => try builder.appendSlice("<lambda>"),
        Value.b_func => try builder.appendSlice("<builtin function>"),
        Value.b_form => try builder.appendSlice("<builtin special form>"),
    }
}

fn consToString(x: Cons, builder: *std.ArrayList(u8)) !void {
    switch (x.cdr.*) {
        Value.cons => |next| {
            // List
            try toStringInner(x.car, builder);
            if (x.cdr == empty()) return;
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

pub fn _caddr(x: ValueRef) ValueRef {
    return _cddr(x).cons.car;
}
