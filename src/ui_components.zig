const std = @import("std");

pub const Vec2 = struct { x: f32 = 0, y: f32 = 0 };
pub const Size = struct { width: f32 = 0, height: f32 = 0 };
pub const Rect = struct { x: f32 = 0, y: f32 = 0, width: f32 = 0, height: f32 = 0 };

pub const Color = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,
    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
};

pub const Direction = enum { left_to_right, top_to_bottom };
pub const Align = enum { start, center, end };
pub const Axis = enum { width, height };
pub const SizingKind = enum { fit, grow, fixed, percent };

pub const Sizing = struct {
    kind: SizingKind = .fit,
    value: f32 = 0,
    min: f32 = 0,
    max: f32 = std.math.floatMax(f32),

    pub fn fit() Sizing {
        return .{ .kind = .fit };
    }

    pub fn grow() Sizing {
        return .{ .kind = .grow };
    }

    pub fn fixed(px: f32) Sizing {
        return .{ .kind = .fixed, .value = px, .min = px, .max = px };
    }

    /// Fraction from 0 to 1; percent(0.5) means half of available space.
    pub fn percent(fraction: f32) Sizing {
        return .{ .kind = .percent, .value = fraction };
    }

    pub fn constrainedGrow(min: f32, max: f32) Sizing {
        return .{ .kind = .grow, .min = min, .max = max };
    }
};

pub const Padding = struct {
    left: f32 = 0,
    right: f32 = 0,
    top: f32 = 0,
    bottom: f32 = 0,

    pub fn all(v: f32) Padding {
        return .{ .left = v, .right = v, .top = v, .bottom = v };
    }

    pub fn xy(x: f32, y: f32) Padding {
        return .{ .left = x, .right = x, .top = y, .bottom = y };
    }

    pub fn horizontal(self: Padding) f32 {
        return self.left + self.right;
    }

    pub fn vertical(self: Padding) f32 {
        return self.top + self.bottom;
    }
};

pub const Layout = struct {
    direction: Direction = .left_to_right,
    width: Sizing = .fit(),
    height: Sizing = .fit(),
    padding: Padding = .{},
    gap: f32 = 0,
    align_x: Align = .start,
    align_y: Align = .start,
};

pub const ElementKind = enum { container, rectangle, text };

pub const Element = struct {
    id: u64 = 0,
    parent: ?usize = null,
    first_child: ?usize = null,
    next_sibling: ?usize = null,
    layout: Layout = .{},
    kind: ElementKind = .container,
    color: Color = Color.transparent,
    text: []const u8 = "",
    /// Optional known text dimensions supplied by the caller.
    intrinsic: Size = .{},
    bounds: Rect = .{},
};

pub const DrawCommand = struct {
    id: u64,
    kind: ElementKind,
    bounds: Rect,
    color: Color,
    text: []const u8,
};

pub const max_elements = 2048;
pub const max_commands = 2048;

/// Fixed-capacity, allocation-free per-frame layout context.
/// Reuse one Context for the lifetime of your UI.
pub const Context = struct {
    elements: [max_elements]Element = undefined,
    commands: [max_commands]DrawCommand = undefined,
    stack: [max_elements]usize = undefined,
    element_count: usize = 0,
    command_count: usize = 0,
    stack_count: usize = 0,
    viewport: Size = .{},

    pub fn init() Context {
        return .{};
    }

    pub fn beginFrame(self: *Context, viewport: Size) void {
        self.element_count = 0;
        self.command_count = 0;
        self.stack_count = 0;
        self.viewport = viewport;
    }

    /// Push a container. Subsequent elements become its children until end().
    pub fn begin(
        self: *Context,
        id: u64,
        layout: Layout,
        color: Color,
    ) error{CapacityExceeded}!void {
        const idx = try self.addElement(.{
            .id = id,
            .layout = layout,
            .color = color,
            .kind = .container,
        });
        try self.push(idx);
    }

    pub fn rect(
        self: *Context,
        id: u64,
        layout: Layout,
        color: Color,
    ) error{CapacityExceeded}!void {
        _ = try self.addElement(.{
            .id = id,
            .layout = layout,
            .color = color,
            .kind = .rectangle,
        });
    }

    pub fn text(
        self: *Context,
        id: u64,
        value: []const u8,
        measured: Size,
        layout: Layout,
        color: Color,
    ) error{CapacityExceeded}!void {
        _ = try self.addElement(.{
            .id = id,
            .layout = layout,
            .color = color,
            .kind = .text,
            .text = value,
            .intrinsic = measured,
        });
    }

    pub fn end(self: *Context) void {
        if (self.stack_count > 0) self.stack_count -= 1;
    }

    /// Resolves the element tree and returns flat draw commands.
    pub fn endFrame(self: *Context) []const DrawCommand {
        if (self.element_count == 0) return self.commands[0..0];

        self.elements[0].bounds = .{
            .x = 0,
            .y = 0,
            .width = self.viewport.width,
            .height = self.viewport.height,
        };

        self.resolveChildren(0);
        self.command_count = 0;
        self.emit(0);

        return self.commands[0..self.command_count];
    }

    /// Returns the topmost command ID containing the point, if any.
    pub fn hitTest(self: *const Context, point: Vec2) ?u64 {
        var i = self.command_count;

        while (i > 0) {
            i -= 1;
            const r = self.commands[i].bounds;

            if (point.x >= r.x and
                point.y >= r.y and
                point.x < r.x + r.width and
                point.y < r.y + r.height)
            {
                return self.commands[i].id;
            }
        }

        return null;
    }

    fn addElement(self: *Context, e: Element) error{CapacityExceeded}!usize {
        if (self.element_count >= max_elements)
            return error.CapacityExceeded;

        const idx = self.element_count;
        self.element_count += 1;
        self.elements[idx] = e;

        if (self.stack_count > 0) {
            const parent_idx = self.stack[self.stack_count - 1];
            self.elements[idx].parent = parent_idx;

            if (self.elements[parent_idx].first_child) |first| {
                var sibling = first;

                while (self.elements[sibling].next_sibling) |next| {
                    sibling = next;
                }

                self.elements[sibling].next_sibling = idx;
            } else {
                self.elements[parent_idx].first_child = idx;
            }
        } else if (idx != 0) {
            // Elements outside an explicit container are attached to the root.
            self.elements[idx].parent = 0;

            if (self.elements[0].first_child) |first| {
                var sibling = first;

                while (self.elements[sibling].next_sibling) |next| {
                    sibling = next;
                }

                self.elements[sibling].next_sibling = idx;
            } else {
                self.elements[0].first_child = idx;
            }
        }

        return idx;
    }

    fn push(self: *Context, idx: usize) error{CapacityExceeded}!void {
        if (self.stack_count >= max_elements)
            return error.CapacityExceeded;

        self.stack[self.stack_count] = idx;
        self.stack_count += 1;
    }

    fn measure(self: *Context, idx: usize, axis: Axis) f32 {
        const e = self.elements[idx];
        const own = if (axis == .width) e.intrinsic.width else e.intrinsic.height;
        const padding = if (axis == .width)
            e.layout.padding.horizontal()
        else
            e.layout.padding.vertical();

        if (e.first_child == null) return own + padding;

        const main_axis =
            (e.layout.direction == .left_to_right and axis == .width) or
            (e.layout.direction == .top_to_bottom and axis == .height);

        var sum: f32 = 0;
        var cross: f32 = 0;
        var count: usize = 0;
        var child = e.first_child;

        while (child) |c| : (child = self.elements[c].next_sibling) {
            const value = self.measure(c, axis);

            if (main_axis) {
                sum += value;
            } else {
                cross = @max(cross, value);
            }

            count += 1;
        }

        if (main_axis and count > 1) {
            sum += e.layout.gap * @as(f32, @floatFromInt(count - 1));
        }

        return (if (main_axis) sum else cross) + padding;
    }

    fn clampSize(s: Sizing, value: f32) f32 {
        return @max(s.min, @min(s.max, value));
    }

    fn resolveChildren(self: *Context, parent_idx: usize) void {
        const parent = self.elements[parent_idx];

        const content_x = parent.bounds.x + parent.layout.padding.left;
        const content_y = parent.bounds.y + parent.layout.padding.top;
        const inner_w = @max(
            0,
            parent.bounds.width - parent.layout.padding.horizontal(),
        );
        const inner_h = @max(
            0,
            parent.bounds.height - parent.layout.padding.vertical(),
        );

        const horizontal = parent.layout.direction == .left_to_right;
        const available_main = if (horizontal) inner_w else inner_h;
        const available_cross = if (horizontal) inner_h else inner_w;

        var total_fixed: f32 = 0;
        var grow_weight: f32 = 0;
        var count: usize = 0;
        var child = parent.first_child;

        while (child) |c| : (child = self.elements[c].next_sibling) {
            const e = self.elements[c];
            const main_sizing = if (horizontal)
                e.layout.width
            else
                e.layout.height;
            const measured = self.measure(
                c,
                if (horizontal) .width else .height,
            );

            if (main_sizing.kind == .grow) {
                grow_weight += 1;
            } else {
                total_fixed += switch (main_sizing.kind) {
                    .fixed => main_sizing.value,
                    .percent => available_main * main_sizing.value,
                    .fit => measured,
                    .grow => 0,
                };
            }

            count += 1;
        }

        if (count > 1) {
            total_fixed += parent.layout.gap *
                @as(f32, @floatFromInt(count - 1));
        }

        const grow_space = @max(0, available_main - total_fixed);
        var cursor = if (horizontal) content_x else content_y;

        child = parent.first_child;

        while (child) |c| : (child = self.elements[c].next_sibling) {
            const e = self.elements[c];
            const ws = e.layout.width;
            const hs = e.layout.height;

            const main_sizing = if (horizontal) ws else hs;
            const cross_sizing = if (horizontal) hs else ws;

            const main_measured = self.measure(
                c,
                if (horizontal) .width else .height,
            );
            const cross_measured = self.measure(
                c,
                if (horizontal) .height else .width,
            );

            const main_size = clampSize(main_sizing, switch (main_sizing.kind) {
                .fixed => main_sizing.value,
                .percent => available_main * main_sizing.value,
                .fit => main_measured,
                .grow => if (grow_weight > 0)
                    grow_space / grow_weight
                else
                    0,
            });

            const cross_size = clampSize(cross_sizing, switch (cross_sizing.kind) {
                .fixed => cross_sizing.value,
                .percent => available_cross * cross_sizing.value,
                .fit => cross_measured,
                .grow => available_cross,
            });

            const cross_align = if (horizontal)
                parent.layout.align_y
            else
                parent.layout.align_x;

            const cross_origin = if (horizontal) content_y else content_x;

            const cross_pos = cross_origin + switch (cross_align) {
                .start => 0,
                .center => (available_cross - cross_size) / 2,
                .end => available_cross - cross_size,
            };

            if (horizontal) {
                self.elements[c].bounds = .{
                    .x = cursor,
                    .y = cross_pos,
                    .width = main_size,
                    .height = cross_size,
                };
            } else {
                self.elements[c].bounds = .{
                    .x = cross_pos,
                    .y = cursor,
                    .width = cross_size,
                    .height = main_size,
                };
            }

            cursor += main_size + parent.layout.gap;
            self.resolveChildren(c);
        }
    }

    fn emit(self: *Context, idx: usize) void {
        const e = self.elements[idx];

        if (self.command_count < max_commands and
            (e.kind != .container or e.color.a != 0 or e.text.len > 0))
        {
            self.commands[self.command_count] = .{
                .id = e.id,
                .kind = e.kind,
                .bounds = e.bounds,
                .color = e.color,
                .text = e.text,
            };

            self.command_count += 1;
        }

        var child = e.first_child;

        while (child) |c| : (child = self.elements[c].next_sibling) {
            self.emit(c);
        }
    }
};

test "fixed and grow sizing resolve children" {
    var ui = Context.init();

    ui.beginFrame(.{ .width = 800, .height = 600 });

    try ui.begin(1, .{
        .direction = .left_to_right,
        .width = Sizing.grow(),
        .height = Sizing.grow(),
        .padding = Padding.all(10),
        .gap = 20,
    }, .{ .r = 20, .g = 20, .b = 20, .a = 255 });

    try ui.rect(2, .{
        .width = Sizing.fixed(100),
        .height = Sizing.grow(),
    }, .{ .r = 255, .a = 255 });

    try ui.rect(3, .{
        .width = Sizing.grow(),
        .height = Sizing.grow(),
    }, .{ .g = 255, .a = 255 });

    ui.end();

    const commands = ui.endFrame();

    try std.testing.expect(commands.len >= 3);
    try std.testing.expectEqual(@as(f32, 100), ui.elements[1].bounds.width);
    try std.testing.expectEqual(@as(f32, 660), ui.elements[2].bounds.width);
}

test "percent sizing" {
    var ui = Context.init();

    ui.beginFrame(.{ .width = 400, .height = 300 });

    try ui.begin(1, .{
        .width = Sizing.grow(),
        .height = Sizing.grow(),
    }, .{});

    try ui.rect(2, .{
        .width = Sizing.percent(0.5),
        .height = Sizing.fixed(20),
    }, .{ .a = 255 });

    ui.end();

    _ = ui.endFrame();

    try std.testing.expectEqual(@as(f32, 200), ui.elements[1].bounds.width);
}
