const std = @import("std");

const C = @import("common.zig");
const S = @import("symbol.zig");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const alloc = arena.allocator();

const Value = C.Value;
// const ValueRef = C.ValueRef;

pub const ValueRef = struct {
    ptr: *Value,

    pub const Self = @This();

    pub fn tag(self: *const Self) C.ValueTag {
        return @as(C.ValueTag, self.get().*);
    }

    pub inline fn get(self: *const Self) *const Value {
        return self.ptr;
    }

    pub fn getMut(self: *Self) *Value {
        return self.ptr;
    }

    pub fn car(self: *const Self) ValueRef {
        return self.get().cons.car;
    }

    pub fn cadr(self: *const Self) ValueRef {
        return self.cdr().car();
    }

    pub fn caddr(self: *const Self) ValueRef {
        return self.cdr().cdr().car();
    }

    pub fn cdr(self: *const Self) ValueRef {
        return self.get().cons.cdr;
    }

    pub fn symbol(self: *const Self) S.ID {
        return self.get().symbol;
    }

    pub fn number(self: *const Self) i64 {
        return self.get().number;
    }

    pub fn bfunc(self: *const Self) u64 {
        return self.get().b_func;
    }

    pub fn bform(self: *const Self) u64 {
        return self.get().b_form;
    }

    pub fn lambda(self: *const Self) ValueRef {
        return self.get().lambda;
    }

    pub fn setValue(self: *Self, val: Value) void {
        self.getMut().* = val;
    }

    pub fn isSymbol(self: *const Self) bool {
        return self.get().* == .symbol;
    }

    pub fn isCons(self: *const Self) bool {
        return self.get().* == .cons;
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.get() == C.empty().get();
    }
};

pub fn newValue(x: Value) !ValueRef {
    std.log.debug("alloc.create {} bytes for {}.{s}", .{ @sizeOf(Value), Value, @tagName(x) });
    const ptr: *Value = try alloc.create(Value);
    ptr.* = x;
    return ValueRef{ .ptr = ptr };
}
