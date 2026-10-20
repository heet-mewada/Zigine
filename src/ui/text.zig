const font = @import("font.zig");

pub const Line = struct {
    start: usize,
    end: usize,
    next: usize,
};

/// Measures a single line in pixels, excluding its final character spacing.
pub fn measureLine(value: []const u8, scale: i32) i32 {
    var count: i32 = 0;

    for (value) |character| {
        if (character == '\n') break;
        count += 1;
    }

    if (count == 0) return 0;

    return count * font.advance(scale) - font.CHAR_SPACING * scale;
}

/// Returns the next line's byte range.
/// A max_width <= 0 disables automatic wrapping.
pub fn nextLine(
    value: []const u8,
    start: usize,
    max_width: i32,
    scale: i32,
) Line {
    if (start >= value.len) {
        return .{ .start = start, .end = start, .next = start };
    }

    if (value[start] == '\n') {
        return .{ .start = start, .end = start, .next = start + 1 };
    }

    var cursor = start;
    var last_space: ?usize = null;
    var width: i32 = 0;

    while (cursor < value.len and value[cursor] != '\n') : (cursor += 1) {
        const next_width = width + font.advance(scale);

        if (max_width > 0 and next_width > max_width and cursor > start) {
            if (last_space) |space| {
                if (space > start) {
                    var next = space + 1;
                    while (next < value.len and value[next] == ' ') : (next += 1) {}

                    return .{
                        .start = start,
                        .end = space,
                        .next = next,
                    };
                }
            }

            return .{
                .start = start,
                .end = cursor,
                .next = cursor,
            };
        }

        if (value[cursor] == ' ') last_space = cursor;
        width = next_width;
    }

    const end = cursor;
    const next = if (cursor < value.len and value[cursor] == '\n')
        cursor + 1
    else
        cursor;

    return .{
        .start = start,
        .end = end,
        .next = next,
    };
}
