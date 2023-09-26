const std = @import("std");
const common = @import("common.zig");
const alloc = common.alloc;

pub const Token = struct {
    line: []const u8,
    index: usize,
    kind: TokenKind,
};

pub const TokenKind = union(enum) {
    int: i64,
    symbol: []const u8,
    left, // (
    right, // )
    quote, // '
    nil, // nil
};

fn isSymbolChar(c: u8) bool {
    return !std.ascii.isWhitespace(c) and c != ')' and c != '(' and c != '\'';
}

pub fn tokenize(code: []const u8) []const Token {
    var toks = std.ArrayList(Token).init(alloc); // defer deinit?

    var i: usize = 0;
    var line_head_pos: usize = 0;
    while (i < code.len) {
        const ascii = std.ascii;

        if (i == 0 or code[i - 1] == '\n') line_head_pos = i;
        const line_head = code[line_head_pos..];
        const line_pos = i - line_head_pos;

        if (ascii.isWhitespace(code[i])) {
            i += 1;
            continue;
        }

        if (code[i] == ';') {
            i += 1;
            while (i < code.len and code[i] != '\n') i += 1;
            continue;
        }

        if (code[i] == '(') {
            toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind.left }) catch unreachable;
            i += 1;
            continue;
        }

        if (code[i] == ')') {
            toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind.right }) catch unreachable;
            i += 1;
            continue;
        }

        if (code[i] == '\'') {
            toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind.quote }) catch unreachable;
            i += 1;
            continue;
        }

        if (ascii.isDigit(code[i])) {
            var begin = i;
            while (i < code.len and ascii.isDigit(code[i]))
                i += 1;
            const val = std.fmt.parseInt(i64, code[begin..i], 10) catch unreachable;
            toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind{ .int = val } }) catch unreachable;
            continue;
        }

        // All other chars are parts of as symbol.
        {
            var begin = i;
            while (i < code.len and isSymbolChar(code[i]))
                i += 1;
            const sym = code[begin..i];
            // special symbol
            if (std.mem.eql(u8, sym, "nil")) {
                toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind.nil }) catch unreachable;
                continue;
            }
            toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind{ .symbol = sym } }) catch unreachable;
            continue;
        }
    }
    return toks.items;
}
