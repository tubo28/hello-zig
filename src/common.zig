const std = @import("std");

const S = @import("symbol.zig");
const M = @import("mem.zig");

pub const ValueRef = M.ValueRef;

const SymbolID = S.ID;
const EnvRef = ValueRef;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const alloc = gpa.allocator();

pub const Cons = struct {
    car: ValueRef,
    cdr: ValueRef,
};

pub const ValueTag = enum { number, symbol, cons, lambda, b_func, b_form };
/// Node of tree.
/// It is a branch only if cons, otherwise leaf.
pub const Value = union(ValueTag) {
    number: i64,
    symbol: SymbolID,
    cons: Cons,
    lambda: ValueRef, // (params closure body)
    b_func: usize, // Index of table
    b_form: usize,
};

pub fn newCons(car: ValueRef, cdr: ValueRef) !ValueRef {
    return M.newValue(Value{ .cons = Cons{ .car = car, .cdr = cdr } });
}

/// empty is a ConsCell such that both its car and cdr are itself.
pub fn empty() ValueRef {
    return empty_opt.?;
}

pub fn init() !void {
    var e = try M.newValue(undefined);
    e.setValue(Value{ .cons = Cons{ .car = e, .cdr = e } });
    empty_opt = e;

    try initSpecialSymbol("#t", &t_opt);
    try initSpecialSymbol("#f", &f_opt);
}

fn initSpecialSymbol(sym: []const u8, dst: *?ValueRef) !void {
    const ptr = try M.newValue(Value{ .symbol = try S.getOrRegister(sym) });
    dst.* = ptr;
}

var f_opt: ?ValueRef = null;
var t_opt: ?ValueRef = null;
var empty_opt: ?ValueRef = null;

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
    while (!h.isEmpty()) {
        std.debug.assert(h.isCons()); // is cons?
        std.debug.assert(list.items.len < buf.len);
        list.appendAssumeCapacity(h.car());
        h = h.cdr();
    }
    return list;
}

pub fn listLength(cons_list: ValueRef) usize {
    std.debug.assert(cons_list.isCons());
    if (cons_list.isEmpty()) return 0;
    return 1 + listLength(cons_list.cdr());
}

pub fn toConsList(list: []ValueRef) !ValueRef {
    if (list.len == 0) return empty();
    return try newCons(list[0], try toConsList(list[1..]));
}

/// The "deep equal" function for values.
pub fn deepEql(x: ValueRef, y: ValueRef) bool {
    if (x.isEmpty() or y.isEmpty()) return x.get() == y.get();
    if (x.tag() != y.tag()) return false;
    switch (x.get().*) {
        Value.number => |x_| return x_ == y.number(),
        Value.symbol => |x_| return x_ == y.symbol(),
        Value.b_func => |x_| return x_ == y.bfunc(),
        Value.b_form => |x_| return x_ == y.bform(),
        Value.cons => |x_| return deepEql(x_.car, y.car()) and deepEql(x_.cdr, y.cdr()),
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
    if (cell.isEmpty()) {
        try builder.appendSlice("()");
        return;
    }
    switch (cell.get().*) {
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
    switch (x.cdr.get().*) {
        Value.cons => |next| {
            // List
            try toStringInner(x.car, builder);
            if (x.cdr.isEmpty()) return;
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

// // TODO: remove this
// pub fn _car(x: ValueRef) ValueRef {
//     return x.car();
// }

// pub fn _cdr(x: ValueRef) ValueRef {
//     return x.cdr();
// }

// pub fn _cddr(x: ValueRef) ValueRef {
//     return _cdr(x).cdr();
// }

// pub fn _cadr(x: ValueRef) ValueRef {
//     return _cdr(x).car();
// }

// pub fn _caddr(x: ValueRef) ValueRef {
//     return _cddr(x).car();
// }
