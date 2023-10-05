const std = @import("std");

const S = @import("symbol.zig");
const C = @import("common.zig");

const ValueRef = C.ValueRef;
const SymbolID = S.ID;

const Map = std.AutoHashMap(SymbolID, ValueRef);

fn newMap() !*Map {
    const ret = try C.alloc.create(Map);
    ret.* = Map.init(C.alloc);
    return ret;
}

pub const Env = struct {
    map: *const Map,
    parent: ?*const Env,

    const Self = @This();
    pub const Ref = *const Self;

    pub fn new() !Env.Ref {
        var ret = try C.alloc.create(Self);
        ret.* = Env{ .map = try newMap(), .parent = null };
        return ret;
    }

    pub fn overwriteOne(self: *const Self, k: SymbolID, v: ValueRef) !Env.Ref {
        var m = try newMap();
        try m.put(k, v);
        var ret = try C.alloc.create(Self);
        ret.* = Env{ .map = m, .parent = self };
        return ret;
    }

    pub fn overwrite(self: *const Self, kvs: []struct { SymbolID, ValueRef }) !Env.Ref {
        var m = try newMap();
        for (kvs) |kv| try m.put(kv[0], kv[1]);
        var ret = try C.alloc.create(Self);
        ret.* = Env{ .map = m, .parent = self };
        return ret;
    }

    pub fn get(self: *const Self, k: SymbolID) ?ValueRef {
        if (self.map.get(k)) |v| return v;
        if (self.parent) |p| return p.get(k);
        return null;
    }
};