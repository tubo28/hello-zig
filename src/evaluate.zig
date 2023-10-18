const std = @import("std");

const C = @import("common.zig");
const S = @import("symbol.zig");
const M = @import("macro.zig");

const Env = @import("env.zig").Env;
const EnvRef = Env.Ref;
const EvalResult = C.EvalResult;
const Function = C.Function;
const SymbolID = S.ID;
const Value = C.Value;
const ValueRef = C.ValueRef;
const Macro = C.Macro;
const MacroRule = C.MacroRule;

const Token = @import("tokenize.zig").Token;

const Builtin = @import("builtin.zig");

pub fn evaluate(x: ValueRef, env: EnvRef) anyerror!EvalResult {
    switch (x.*) {
        Value.number => return .{ x, env },
        Value.function, Value.b_func, Value.b_spf, Value.macro => unreachable,
        Value.symbol => |sym| return if (env.get(sym)) |ent| .{ ent, env } else .{ x, env },
        Value.binding => |b| return .{ b.ref, env },
        Value.cons => |cons| {
            if (x == C.empty()) {
                std.log.err("cannot evaluate empty list", .{});
                unreachable;
            }

            if (cons.car.* == .symbol and
                if (env.get(cons.car.symbol)) |v| v.* == .macro else false)
            {
                const name = cons.car.symbol;
                std.log.err("macro `{s}`", .{S.getName(name).?});
                const macro = env.get(name).?.macro;
                const matched = try matches(x, macro);
                if (matched == null) {
                    std.log.err("expression doesn't match any rule of macro {s}", .{S.getName(macro.name).?});
                    unreachable;
                }
                const rule, const map = matched.?;
                const expr = expand(x, rule, map);
                return evaluate(expr, env);
            }

            // Call something
            const c = try toCallable(cons.car, env);
            var buf: [100]ValueRef = undefined;
            const args = C.toArrayListUnmanaged(cons.cdr, &buf);
            return call(c, args.items, env);
        },
    }
}

fn expand(input: ValueRef, rule: MacroRule, map: SymbolMap) ValueRef {
    const map_to = rule.template;
    _ = map_to;
    _ = map;
    return input;
}

// Returns which MacroRule input matches to.
fn matches(input: ValueRef, macro: *const Macro) !?struct { MacroRule, SymbolMap } {
    var result = SymbolMap.init(C.alloc);
    for (macro.rules) |r| {
        result.clearRetainingCapacity();
        if (try matchPattern(macro.name, r.pattern, input, &result)) {
            return .{ r, result };
        }
    }
    return null;
}

fn symbolp(x: ValueRef) ?SymbolID {
    switch (x.*) {
        Value.symbol => |s| return s,
        else => return null,
    }
}

fn testMatches(name: []const u8, pat: []const u8, in: []const u8) !bool {
    const P = @import("parse.zig");
    const T = @import("tokenize.zig");
    const p = (try P.parse(try T.tokenize(pat)))[0];
    const i = (try P.parse(try T.tokenize(in)))[0];
    var result = SymbolMap.init(C.alloc);
    const ret = try matchPattern(try S.getOrRegister(name), p, i, &result);
    std.log.debug("match result:", .{});
    var iter = result.iterator();
    while (iter.next()) |entry| {
        std.log.debug("{s} -> ", .{S.getName(entry.key_ptr.*).?});
        const items = entry.value_ptr.*.items;
        for (items[0..items.len]) |v|
            std.log.debug("  variadic {any}", .{v});
    }
    return ret;
}

test "macro/patternMatching" {
    std.testing.log_level = std.log.Level.debug;
    try S.init();
    try std.testing.expect(try testMatches("macro", "(_ a b)", "(macro 0 1)"));
    try std.testing.expect(!try testMatches("macro", "(_ a b)", "(bad 0 1)"));
    try std.testing.expect(try testMatches("macro", "(_ (a (b c) d))", "(macro (0 (1 2) 3))"));
    try std.testing.expect(!try testMatches("macro", "(_ (a (b c) d))", "(macro (0 1 2 3))"));
    // TODO
    // try std.testing.expect(try matches("macro", "(_ a ...)", "(macro)"));
    try std.testing.expect(try testMatches("macro", "(_ a ...)", "(macro 0)"));
    try std.testing.expect(try testMatches("macro", "(_ a ...)", "(macro 0 1)"));
    try std.testing.expect(try testMatches("macro", "(_ a ...)", "(macro 0 1 2)"));
    try std.testing.expect(!try testMatches("macro", "(_ (a b) ...)", "(macro 0 1 2)"));
    try std.testing.expect(try testMatches("macro", "(_ (a b) ...)", "(macro (0 1))"));
    try std.testing.expect(try testMatches("macro", "(_ (a b) ...)", "(macro (0 1) (2 3))"));
}

const SymbolMap = std.AutoHashMap(SymbolID, *std.ArrayList(ValueRef));

// name:
//  if
// template:
// (define-syntax if
//   (syntax-rules ()
//     ((_ test then else)
//      (cond (test then)
//            (else else)))))
// epxr:
// (if a foo bar)
fn matchPattern(name: SymbolID, pattern: ValueRef, input: ValueRef, map: *SymbolMap) !bool {
    // TODO: Check pattern has duplicated symbols
    const self_name = try S.getOrRegister("_");
    const dots = try S.getOrRegister("...");

    switch (pattern.*) {
        Value.number => |x| {
            if (input.* != .number) return false;
            return x == input.number;
        },
        Value.symbol => |s| {
            const get_result = try map.getOrPut(s);
            const list = get_result.value_ptr;
            if (!get_result.found_existing) {
                var new = std.ArrayList(ValueRef).init(C.alloc);
                list.* = try C.new(std.ArrayList(ValueRef), new);
            }
            try list.*.append(input);
            return true;
        },
        Value.cons => |cons| {
            if (input.* != .cons) return false;
            if (symbolp(cons.car) == self_name) {
                if (symbolp(input.cons.car) != name) return false;
                return matchPattern(name, cons.cdr, input.cons.cdr, map);
            }

            var tmp: [100]ValueRef = undefined;
            var tmp2: [100]ValueRef = undefined;
            var pattern_seq = C.toArrayListUnmanaged(pattern, &tmp);
            const input_seq = C.toArrayListUnmanaged(input, &tmp2);

            // If not variadic template.
            if (pattern_seq.items.len == input_seq.items.len) {
                for (pattern_seq.items, input_seq.items) |p, i|
                    if (!try matchPattern(name, p, i, map)) return false;
                return true;
            }

            if (pattern_seq.items.len < 2) return false; // pattern should contain 'a ...'

            // If length of pattern and input is different, the last symbol of pattern must be '...'.
            const last = pattern_seq.getLast();
            if (last.* != .symbol or last.symbol != dots) return false;
            // Too short?
            if (input_seq.items.len < pattern_seq.items.len - 1) return false;
            // Check before 'pat ...)'
            const pattern_len = pattern_seq.items.len;
            for (pattern_seq.items[0 .. pattern_len - 2], input_seq.items[0 .. pattern_len - 2]) |t, i|
                if (!try matchPattern(name, t, i, map)) return false;
            // Check 'pat ...)'
            const pat = pattern_seq.items[pattern_len - 2];
            for (input_seq.items[pattern_len - 2 ..]) |i|
                if (!try matchPattern(name, pat, i, map)) return false;
            return true;
        },
        else => {
            std.log.err("invalid template", .{});
            unreachable;
        },
    }
    unreachable;
}

const Callable = union(enum) {
    bsf: *const Builtin.SpecialForm,
    bfunc: *const Builtin.Function,
    func: *const Function,
};

fn toCallable(car: *const C.Value, env: EnvRef) !Callable {
    if (car.* == .cons) {
        // example: ((lambda (x) (+ x x)) 1)
        const lmd, _ = try evaluate(car, env);
        return Callable{ .func = lmd.function };
    }

    var callable: ValueRef = undefined;
    var name: SymbolID = undefined;
    switch (car.*) {
        Value.symbol => |s| {
            if (env.get(s)) |v| {
                name = s;
                callable = v;
            } else {
                std.log.err("not callable: {}", .{car.*});
                unreachable;
            }
        },
        Value.binding => |b| {
            name = b.symbol;
            callable = b.ref;
        },
        else => {
            std.log.err("not callable: {}", .{car.*});
            unreachable;
        },
    }

    switch (callable.*) {
        Value.function => |f_| return Callable{ .func = f_ },
        Value.b_func => |bf| return Callable{ .bfunc = Builtin.func[bf] },
        Value.b_spf => |bs| return Callable{ .bsf = Builtin.spf[bs] },
        else => |other| {
            std.log.err("symbol `{s}` is bound to non-callable value: {any}", .{ S.getName(name).?, other });
            unreachable;
        },
    }
}

fn call(callable: Callable, args: []ValueRef, env: EnvRef) anyerror!EvalResult {
    switch (callable) {
        Callable.bsf => |form| return form(args, env),
        Callable.bfunc => |func| {
            var to: [100]ValueRef = undefined;
            try evalAll(args, env, &to);
            return .{ try func(to[0..args.len]), env };
        },
        Callable.func => |func| {
            var to: [100]ValueRef = undefined;
            try evalAll(args, env, &to);
            return .{ try callFunction(func, to[0..args.len]), env };
        },
    }
}

fn evalAll(xs: []ValueRef, env: EnvRef, to: []ValueRef) !void {
    for (xs, 0..) |x, i| {
        const ret, _ = try evaluate(x, env);
        to[i] = ret;
    }
}

fn callFunction(func: *const Function, args: []ValueRef) anyerror!ValueRef {
    std.debug.assert(args.len == func.params.len);
    const len = func.params.len;

    // Make func_env
    var new_binds: [100]struct { SymbolID, ValueRef } = undefined;
    // Names of function arguments overwrites function's namespace (shadowing).
    for (args, 0..) |arg, i| new_binds[i] = .{ func.params[i], arg };
    var func_env = try func.env.overwrite(new_binds[0..len]);

    // Eval body.
    std.debug.assert(func.body.len > 0);
    var ret: ValueRef = C.empty();
    for (func.body) |expr| ret, func_env = try evaluate(expr, func_env);
    return ret;
}
