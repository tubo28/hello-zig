const std = @import("std");

const C = @import("common.zig");
const S = @import("symbol.zig");

const alloc = C.alloc;

pub const Token = struct {
    line: []const u8,
    index: usize,
    kind: TokenKind,
};

pub const TokenKind = union(enum) {
    int: i64,
    symbol: S.ID,
    left, // ( [
    right, // ) ]
    dot, // .
    quote, // '
    f, // #f
};

fn isSymbolChar(c: u8) bool {
    return !std.ascii.isWhitespace(c) and c != '(' and c != ')' and c != '[' and c != ']' and c != '\'';
}

pub fn tokenize(code: []const u8) ![]const Token {
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

        if (code[i] == '(' or code[i] == '[') {
            try toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind.left });
            i += 1;
            continue;
        }

        if (code[i] == ')' or code[i] == ')') {
            try toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind.right });
            i += 1;
            continue;
        }

        if (code[i] == '.' and !(i + 1 < code.len and code[i + 1] == '.')) {
            try toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind.dot });
            i += 1;
            continue;
        }

        if (code[i] == '\'') {
            try toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind.quote });
            i += 1;
            continue;
        }

        if (isSymbolChar(code[i])) {
            const begin = i;
            while (i < code.len and isSymbolChar(code[i])) i += 1;

            const tok = code[begin..i];
            if (std.fmt.parseInt(i64, tok, 0) catch null) |int| {
                try toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind{ .int = int } });
            } else if (std.mem.eql(u8, tok, "#f")) {
                try toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind.f });
            } else {
                try toks.append(Token{ .line = line_head, .index = line_pos, .kind = TokenKind{ .symbol = try S.getOrRegister(tok) } });
            }
            continue;
        }
        unreachable;
    }
    return toks.toOwnedSlice();
}
