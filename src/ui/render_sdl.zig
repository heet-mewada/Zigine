const font = @import("font.zig");
const text = @import("text.zig");
const ui = @import("ui-components");

pub const TextStyle = struct {
    scale: i32 = 2,
    wrap: bool = true,
};

fn drawGlyph(
    surface: anytype,
    x: i32,
    y: i32,
    character: u8,
    color: anytype,
    clip: ui.Rect,
    scale: i32,
) !void {
    const clip_left: i32 = @intFromFloat(@ceil(clip.x));
    const clip_top: i32 = @intFromFloat(@ceil(clip.y));
    const clip_right: i32 = @intFromFloat(@floor(clip.x + clip.width));
    const clip_bottom: i32 = @intFromFloat(@floor(clip.y + clip.height));

    if (clip_right <= clip_left or clip_bottom <= clip_top) return;

    const rows = font.glyph(character);

    for (rows, 0..) |bits, row| {
        for (0..@intCast(font.GLYPH_WIDTH)) |column| {
            const shift: u3 = @intCast(4 - column);
            const mask: u8 = @as(u8, 1) << shift;

            if ((bits & mask) == 0) continue;

            const px = x + @as(i32, @intCast(column)) * scale;
            const py = y + @as(i32, @intCast(row)) * scale;

            const left = @max(px, clip_left);
            const top = @max(py, clip_top);
            const right = @min(px + scale, clip_right);
            const bottom = @min(py + scale, clip_bottom);

            if (right <= left or bottom <= top) continue;

            try surface.fillRect(.{
                .x = left,
                .y = top,
                .w = right - left,
                .h = bottom - top,
            }, surface.mapRgb(color.r, color.g, color.b));
        }
    }
}

/// Draws text within bounds, clipping it to clip_bounds.
pub fn drawText(
    surface: anytype,
    bounds: ui.Rect,
    value: []const u8,
    color: anytype,
    clip_bounds: ui.Rect,
    style: TextStyle,
) !void {
    if (style.scale <= 0 or value.len == 0) return;

    const max_width: i32 = if (style.wrap)
        @max(0, @as(i32, @intFromFloat(@max(0, bounds.width))))
    else
        0;

    const origin_x: i32 = @intFromFloat(@ceil(bounds.x));
    var cursor_y: i32 = @intFromFloat(@ceil(bounds.y));
    var offset: usize = 0;

    while (offset < value.len) {
        const line = text.nextLine(
            value,
            offset,
            max_width,
            style.scale,
        );

        var cursor_x = origin_x;

        for (value[line.start..line.end]) |character| {
            try drawGlyph(
                surface,
                cursor_x,
                cursor_y,
                character,
                color,
                clip_bounds,
                style.scale,
            );

            cursor_x += font.advance(style.scale);
        }

        offset = line.next;
        cursor_y += font.lineHeight(style.scale);

        // Avoid drawing beyond the text component's vertical bounds.
        if (@as(f32, @floatFromInt(cursor_y)) >= bounds.y + bounds.height) {
            break;
        }

        // Defensive guard against a malformed line range.
        if (line.next <= line.start and line.end == line.start) break;
    }
}
