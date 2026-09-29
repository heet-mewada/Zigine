const std = @import("std");

/// Maximum amount of UTF-8 text stored in a single rope node.
const CHUNK_SIZE = 256;

// ============================================================================
// Text Summary
// ============================================================================

pub const TextSummary = struct {
    bytes: usize,
    chars: usize,
    lines: usize,
    first_line_bytes: usize,
    last_line_bytes: usize,
    longest_line_bytes: usize,
    longest_line: usize,

    pub const empty = TextSummary{
        .bytes = 0,
        .chars = 0,
        .lines = 0,
        .first_line_bytes = 0,
        .last_line_bytes = 0,
        .longest_line_bytes = 0,
        .longest_line = 0,
    };

    pub fn fromText(content: []const u8) TextSummary {
        if (content.len == 0) {
            return empty;
        }

        var result = TextSummary{
            .bytes = content.len,
            .chars = 0,
            .lines = 0,
            .first_line_bytes = 0,
            .last_line_bytes = 0,
            .longest_line_bytes = 0,
            .longest_line = 0,
        };

        var current_line_bytes: usize = 0;
        var current_line: usize = 0;
        var first_newline_found = false;

        var i: usize = 0;

        while (i < content.len) {
            const byte = content[i];

            // A UTF-8 codepoint starts at every byte which is not
            // a continuation byte.
            if ((byte & 0xC0) != 0x80) {
                result.chars += 1;
            }

            if (byte == '\n') {
                if (!first_newline_found) {
                    result.first_line_bytes = current_line_bytes;
                    first_newline_found = true;
                }

                if (current_line_bytes > result.longest_line_bytes) {
                    result.longest_line_bytes = current_line_bytes;
                    result.longest_line = current_line;
                }

                result.lines += 1;

                current_line += 1;
                current_line_bytes = 0;
            } else {
                current_line_bytes += 1;
            }

            i += 1;
        }

        result.last_line_bytes = current_line_bytes;

        if (current_line_bytes > result.longest_line_bytes) {
            result.longest_line_bytes = current_line_bytes;
            result.longest_line = current_line;
        }

        if (!first_newline_found) {
            result.first_line_bytes = current_line_bytes;
        }

        return result;
    }

    pub fn add(
        self: TextSummary,
        rhs: TextSummary,
    ) TextSummary {
        if (self.bytes == 0) {
            return rhs;
        }

        if (rhs.bytes == 0) {
            return self;
        }

        var result = TextSummary{
            .bytes = self.bytes + rhs.bytes,
            .chars = self.chars + rhs.chars,
            .lines = self.lines + rhs.lines,
            .first_line_bytes = self.first_line_bytes,
            .last_line_bytes = rhs.last_line_bytes,
            .longest_line_bytes = self.longest_line_bytes,
            .longest_line = self.longest_line,
        };

        // The entire left side is part of the first line when
        // there are no newlines on the left.
        if (self.lines == 0) {
            result.first_line_bytes =
                self.bytes + rhs.first_line_bytes;
        }

        // The right side becomes part of the last line when
        // there are no newlines on the right.
        if (rhs.lines == 0) {
            result.last_line_bytes =
                self.last_line_bytes + rhs.bytes;
        }

        // A line can cross the boundary between the two summaries.
        const crossing_line =
            self.last_line_bytes + rhs.first_line_bytes;

        if (crossing_line > result.longest_line_bytes) {
            result.longest_line_bytes = crossing_line;

            if (self.lines > 0) {
                result.longest_line = self.lines - 1;
            } else {
                result.longest_line = 0;
            }
        }

        // If the right side has the longest line, its line number
        // must be shifted by the number of lines on the left.
        if (rhs.longest_line_bytes >
            self.longest_line_bytes and
            rhs.longest_line_bytes >= crossing_line)
        {
            result.longest_line_bytes =
                rhs.longest_line_bytes;

            result.longest_line =
                self.lines + rhs.longest_line;
        }

        return result;
    }
};

// ============================================================================
// Point
// ============================================================================

pub const Point = struct {
    /// Zero-based line.
    row: usize,

    /// Zero-based byte column.
    column: usize,
};

// ============================================================================
// Node
// ============================================================================

pub const Node = struct {
    /// Text stored by this node.
    text: []u8,

    /// Treap priority.
    priority: u64,

    /// Left child.
    left: ?*Node,

    /// Right child.
    right: ?*Node,

    /// Cached summary for this node and its subtree.
    summary: TextSummary,

    /// Allocator used to destroy this node.
    allocator: std.mem.Allocator,
};

// ============================================================================
// Rope
// ============================================================================

pub const Rope = struct {
    allocator: std.mem.Allocator,

    root: ?*Node,

    /// Deterministic pseudo-random state for treap priorities.
    random_state: u64,

    // ------------------------------------------------------------------------
    // Initialization
    // ------------------------------------------------------------------------

    pub fn init(
        allocator: std.mem.Allocator,
    ) Rope {
        return Rope{
            .allocator = allocator,
            .root = null,
            .random_state = 0x123456789abcdef0,
        };
    }

    pub fn deinit(
        self: *Rope,
    ) void {
        self.destroyTree(self.root);
        self.root = null;
    }

    fn destroyTree(
        self: *Rope,
        node: ?*Node,
    ) void {
        if (node) |current| {
            self.destroyTree(current.left);
            self.destroyTree(current.right);

            self.allocator.free(current.text);
            self.allocator.destroy(current);
        }
    }

    // ------------------------------------------------------------------------
    // Priority
    // ------------------------------------------------------------------------

    fn nextPriority(
        self: *Rope,
    ) u64 {
        var x = self.random_state;

        // xorshift64
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;

        self.random_state = x;

        return x;
    }

    // ------------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------------

    pub fn summary(
        self: *const Rope,
    ) TextSummary {
        if (self.root) |root| {
            return root.summary;
        }

        return TextSummary.empty;
    }

    pub fn len(
        self: *const Rope,
    ) usize {
        return self.summary().bytes;
    }

    pub fn charCount(
        self: *const Rope,
    ) usize {
        return self.summary().chars;
    }

    pub fn lineCount(
        self: *const Rope,
    ) usize {
        return self.summary().lines + 1;
    }

    // ------------------------------------------------------------------------
    // Node Creation
    // ------------------------------------------------------------------------

    fn createNode(
        self: *Rope,
        content: []const u8,
    ) !*Node {
        const copied =
            try self.allocator.dupe(
                u8,
                content,
            );

        errdefer self.allocator.free(copied);

        const node =
            try self.allocator.create(Node);

        node.* = Node{
            .text = copied,
            .priority = self.nextPriority(),
            .left = null,
            .right = null,
            .summary = TextSummary.fromText(copied),
            .allocator = self.allocator,
        };

        return node;
    }

    fn update(
        node: *Node,
    ) void {
        var result =
            TextSummary.fromText(node.text);

        if (node.left) |left| {
            result =
                left.summary.add(result);
        }

        if (node.right) |right| {
            result =
                result.add(right.summary);
        }

        node.summary = result;
    }

    // ------------------------------------------------------------------------
    // Character Boundary
    // ------------------------------------------------------------------------

    pub fn isCharBoundary(
        self: *const Rope,
        offset: usize,
    ) bool {
        if (offset > self.len()) {
            return false;
        }

        if (offset == 0 or
            offset == self.len())
        {
            return true;
        }

        var current =
            self.root orelse return true;

        var remaining = offset;

        while (true) {
            const left_bytes =
                if (current.left) |left|
                    left.summary.bytes
                else
                    0;

            if (remaining < left_bytes) {
                current = current.left.?;
                continue;
            }

            remaining -= left_bytes;

            if (remaining < current.text.len) {
                if (remaining == 0 or
                    remaining == current.text.len)
                {
                    return true;
                }

                return (current.text[remaining] & 0xC0) != 0x80;
            }

            remaining -= current.text.len;

            if (current.right) |right| {
                current = right;
            } else {
                return remaining == 0;
            }
        }
    }

    // ------------------------------------------------------------------------
    // Split
    // ------------------------------------------------------------------------

    const SplitResult = struct {
        left: ?*Node,
        right: ?*Node,
    };

    fn split(
        node: ?*Node,
        offset: usize,
    ) SplitResult {
        if (node == null) {
            return .{
                .left = null,
                .right = null,
            };
        }

        const current = node.?;

        const left_bytes =
            if (current.left) |left|
                left.summary.bytes
            else
                0;

        if (offset < left_bytes) {
            const parts =
                split(
                    current.left,
                    offset,
                );

            current.left = parts.right;

            update(current);

            return .{
                .left = parts.left,
                .right = current,
            };
        }

        const node_start =
            left_bytes;

        const node_end =
            node_start + current.text.len;

        // Split inside this node's text.
        if (offset > node_start and
            offset < node_end)
        {
            const split_inside =
                offset - node_start;

            const left_text =
                current.text[0..split_inside];

            const right_text =
                current.text[split_inside..];

            const left_node =
                current.allocator.create(Node) catch unreachable;

            const right_node =
                current.allocator.create(Node) catch unreachable;

            const left_copy =
                current.allocator.dupe(
                    u8,
                    left_text,
                ) catch unreachable;

            const right_copy =
                current.allocator.dupe(
                    u8,
                    right_text,
                ) catch unreachable;

            left_node.* = Node{
                .text = left_copy,
                .priority = current.priority,
                .left = current.left,
                .right = null,
                .summary = TextSummary.empty,
                .allocator = current.allocator,
            };

            right_node.* = Node{
                .text = right_copy,
                .priority = current.priority,
                .left = null,
                .right = current.right,
                .summary = TextSummary.empty,
                .allocator = current.allocator,
            };

            update(left_node);
            update(right_node);

            current.allocator.free(
                current.text,
            );

            current.allocator.destroy(
                current,
            );

            return .{
                .left = left_node,
                .right = right_node,
            };
        }

        if (offset == node_start) {
            const left_tree =
                current.left;

            current.left = null;

            update(current);

            return .{
                .left = left_tree,
                .right = current,
            };
        }

        if (offset == node_end) {
            const right_tree =
                current.right;

            current.right = null;

            update(current);

            return .{
                .left = current,
                .right = right_tree,
            };
        }

        // offset is after this node.
        const right_offset =
            offset - node_end;

        const parts =
            split(
                current.right,
                right_offset,
            );

        current.right = parts.left;

        update(current);

        return .{
            .left = current,
            .right = parts.right,
        };
    }

    // ------------------------------------------------------------------------
    // Merge
    // ------------------------------------------------------------------------

    fn merge(
        left: ?*Node,
        right: ?*Node,
    ) ?*Node {
        if (left == null) {
            return right;
        }

        if (right == null) {
            return left;
        }

        const left_node = left.?;
        const right_node = right.?;

        if (left_node.priority >=
            right_node.priority)
        {
            left_node.right =
                merge(
                    left_node.right,
                    right,
                );

            update(left_node);

            return left_node;
        }

        right_node.left =
            merge(
                left,
                right_node.left,
            );

        update(right_node);

        return right_node;
    }

    // ------------------------------------------------------------------------
    // Chunking
    // ------------------------------------------------------------------------

    fn makeChunks(
        self: *Rope,
        content: []const u8,
    ) !std.ArrayList([]const u8) {
        var chunks =
            std.ArrayList([]const u8).empty;

        errdefer chunks.deinit(
            self.allocator,
        );

        var start: usize = 0;

        while (start < content.len) {
            var end =
                @min(
                    start + CHUNK_SIZE,
                    content.len,
                );

            // Never split in the middle of a UTF-8
            // continuation sequence.
            while (end < content.len and
                (content[end] & 0xC0) == 0x80)
            {
                end -= 1;
            }

            if (end == start) {
                end =
                    @min(
                        start + CHUNK_SIZE,
                        content.len,
                    );

                while (end < content.len and
                    (content[end] & 0xC0) == 0x80)
                {
                    end += 1;
                }
            }

            try chunks.append(
                self.allocator,
                content[start..end],
            );

            start = end;
        }

        return chunks;
    }

    // ------------------------------------------------------------------------
    // Insert
    // ------------------------------------------------------------------------

    pub fn insert(
        self: *Rope,
        offset: usize,
        content: []const u8,
    ) !void {
        if (offset > self.len()) {
            return error.InvalidOffset;
        }

        if (!self.isCharBoundary(offset)) {
            return error.NotCharBoundary;
        }

        if (content.len == 0) {
            return;
        }

        if (!std.unicode.utf8ValidateSlice(content)) {
            return error.InvalidUtf8;
        }

        var chunks =
            try self.makeChunks(content);

        defer chunks.deinit(
            self.allocator,
        );

        var inserted: ?*Node = null;

        for (chunks.items) |chunk| {
            const node =
                try self.createNode(chunk);

            inserted =
                merge(
                    inserted,
                    node,
                );
        }

        const parts =
            split(
                self.root,
                offset,
            );

        self.root =
            merge(
                merge(
                    parts.left,
                    inserted,
                ),
                parts.right,
            );
    }

    // ------------------------------------------------------------------------
    // Delete
    // ------------------------------------------------------------------------

    pub fn delete(
        self: *Rope,
        start: usize,
        count: usize,
    ) !void {
        if (start > self.len()) {
            return error.InvalidOffset;
        }

        if (count > self.len() - start) {
            return error.InvalidOffset;
        }

        if (!self.isCharBoundary(start) or
            !self.isCharBoundary(start + count))
        {
            return error.NotCharBoundary;
        }

        if (count == 0) {
            return;
        }

        const first =
            split(
                self.root,
                start,
            );

        const second =
            split(
                first.right,
                count,
            );

        self.destroyTree(
            second.left,
        );

        self.root =
            merge(
                first.left,
                second.right,
            );
    }

    // ------------------------------------------------------------------------
    // Replace
    // ------------------------------------------------------------------------

    pub fn replace(
        self: *Rope,
        start: usize,
        count: usize,
        content: []const u8,
    ) !void {
        if (start > self.len()) {
            return error.InvalidOffset;
        }

        if (count > self.len() - start) {
            return error.InvalidOffset;
        }

        if (!self.isCharBoundary(start) or
            !self.isCharBoundary(start + count))
        {
            return error.NotCharBoundary;
        }

        if (!std.unicode.utf8ValidateSlice(content)) {
            return error.InvalidUtf8;
        }

        try self.delete(
            start,
            count,
        );

        try self.insert(
            start,
            content,
        );
    }

    // ------------------------------------------------------------------------
    // Offset -> Point
    // ------------------------------------------------------------------------

    pub fn offsetToPoint(
        self: *const Rope,
        offset: usize,
    ) !Point {
        if (offset > self.len()) {
            return error.InvalidOffset;
        }

        var current = self.root;
        var remaining = offset;

        var row: usize = 0;
        var column: usize = 0;

        while (current) |node| {
            const left_bytes =
                if (node.left) |left|
                    left.summary.bytes
                else
                    0;

            const left_summary =
                if (node.left) |left|
                    left.summary
                else
                    TextSummary.empty;

            if (remaining < left_bytes) {
                row += left_summary.lines;

                if (left_summary.lines == 0) {
                    column += left_summary.bytes;
                } else {
                    column =
                        left_summary.last_line_bytes;
                }

                current = node.left;
                continue;
            }

            remaining -= left_bytes;

            if (remaining <= node.text.len) {
                var i: usize = 0;

                while (i < remaining) {
                    if (node.text[i] == '\n') {
                        row += 1;
                        column = 0;
                    } else {
                        column += 1;
                    }

                    i += 1;
                }

                return Point{
                    .row = row,
                    .column = column,
                };
            }

            remaining -= node.text.len;

            const node_summary =
                TextSummary.fromText(
                    node.text,
                );

            row += node_summary.lines;

            if (node_summary.lines == 0) {
                column += node_summary.bytes;
            } else {
                column =
                    node_summary.last_line_bytes;
            }

            current = node.right;
        }

        return Point{
            .row = row,
            .column = column,
        };
    }

    // ------------------------------------------------------------------------
    // Point -> Offset
    // ------------------------------------------------------------------------

    pub fn pointToOffset(
        self: *const Rope,
        point: Point,
    ) !usize {
        var current = self.root;
        var offset: usize = 0;

        while (current) |node| {
            const left_summary =
                if (node.left) |left|
                    left.summary
                else
                    TextSummary.empty;

            if (point.row < left_summary.lines) {
                current = node.left;
                continue;
            }

            if (point.row ==
                left_summary.lines and
                point.column <=
                    left_summary.last_line_bytes)
            {
                offset += left_summary.bytes;

                var i: usize = 0;
                var column: usize = 0;

                while (i < node.text.len) {
                    if (column == point.column) {
                        return offset;
                    }

                    if (node.text[i] == '\n') {
                        if (point.row == 0) {
                            break;
                        }

                        return error.InvalidPoint;
                    }

                    column += 1;
                    i += 1;
                }

                if (column == point.column) {
                    return offset + node.text.len;
                }

                return error.InvalidPoint;
            }

            offset += left_summary.bytes;

            var node_lines: usize = 0;
            var last_line_bytes: usize = 0;

            var i: usize = 0;

            while (i < node.text.len) {
                if (node.text[i] == '\n') {
                    node_lines += 1;
                    last_line_bytes = 0;
                } else {
                    last_line_bytes += 1;
                }

                i += 1;
            }

            if (point.row <=
                left_summary.lines +
                    node_lines)
            {
                var target_row =
                    point.row -
                    left_summary.lines;

                var j: usize = 0;
                var col: usize = 0;

                while (j < node.text.len) {
                    if (target_row == 0 and
                        col == point.column)
                    {
                        return offset;
                    }

                    if (node.text[j] == '\n') {
                        if (target_row == 0) {
                            return error.InvalidPoint;
                        }

                        target_row -= 1;
                        col = 0;
                    } else {
                        col += 1;
                    }

                    j += 1;
                    offset += 1;
                }

                if (target_row == 0 and
                    col == point.column)
                {
                    return offset;
                }
            }

            current = node.right;
        }

        if (point.row ==
            self.lineCount() - 1 and
            point.column == 0)
        {
            return self.len();
        }

        return error.InvalidPoint;
    }

    // ------------------------------------------------------------------------
    // Text Extraction
    // ------------------------------------------------------------------------

    pub fn text(
        self: *const Rope,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        const result =
            try allocator.alloc(
                u8,
                self.len(),
            );

        errdefer allocator.free(result);

        try self.copyInto(result);

        return result;
    }

    pub fn copyInto(
        self: *const Rope,
        destination: []u8,
    ) !void {
        if (destination.len < self.len()) {
            return error.BufferTooSmall;
        }

        var offset: usize = 0;

        copyNodeInto(
            self.root,
            destination,
            &offset,
        );
    }

    fn copyNodeInto(
        node: ?*Node,
        destination: []u8,
        offset: *usize,
    ) void {
        if (node) |current| {
            copyNodeInto(
                current.left,
                destination,
                offset,
            );

            @memcpy(
                destination[offset.* .. offset.* + current.text.len],
                current.text,
            );

            offset.* += current.text.len;

            copyNodeInto(
                current.right,
                destination,
                offset,
            );
        }
    }

    // ------------------------------------------------------------------------
    // Visualization
    // ------------------------------------------------------------------------

    pub fn dump(
        self: *const Rope,
    ) void {
        self.dumpWithOptions(true);
    }

    /// Visualization where `show_text` controls whether the entire rope
    /// contents are printed.
    ///
    /// The tree is always printed.
    pub fn dumpWithOptions(
        self: *const Rope,
        show_text: bool,
    ) void {
        std.debug.print(
            "\n========== ROPE ==========\n",
            .{},
        );

        if (show_text) {
            std.debug.print(
                "Text: \"",
                .{},
            );

            self.dumpText(self.root);

            std.debug.print(
                "\"\n",
                .{},
            );
        } else {
            std.debug.print(
                "Text: <hidden>\n",
                .{},
            );
        }

        std.debug.print(
            "Bytes: {}\n",
            .{self.len()},
        );

        std.debug.print(
            "Chars: {}\n",
            .{self.charCount()},
        );

        std.debug.print(
            "Lines: {}\n",
            .{self.lineCount()},
        );

        std.debug.print(
            "\nTree:\n",
            .{},
        );

        if (self.root == null) {
            std.debug.print(
                "└── <empty>\n",
                .{},
            );
        } else {
            self.dumpTree(
                self.root,
                0,
                .root,
            );
        }

        std.debug.print(
            "===========================\n\n",
            .{},
        );
    }

    fn dumpText(
        self: *const Rope,
        node: ?*Node,
    ) void {
        if (node) |current| {
            self.dumpText(
                current.left,
            );

            for (current.text) |byte| {
                switch (byte) {
                    '\n' => std.debug.print(
                        "\\n",
                        .{},
                    ),

                    '\r' => std.debug.print(
                        "\\r",
                        .{},
                    ),

                    '\t' => std.debug.print(
                        "\\t",
                        .{},
                    ),

                    else => std.debug.print(
                        "{c}",
                        .{byte},
                    ),
                }
            }

            self.dumpText(
                current.right,
            );
        }
    }

    const DumpSide = enum {
        root,
        left,
        right,
    };

    fn dumpTree(
        self: *const Rope,
        node: ?*Node,
        depth: usize,
        side: DumpSide,
    ) void {
        if (node == null) {
            return;
        }

        const current = node.?;

        for (0..depth) |_| {
            std.debug.print(
                "    ",
                .{},
            );
        }

        const branch =
            switch (side) {
                .root => "└── ",
                .left => "├── L ",
                .right => "└── R ",
            };

        std.debug.print(
            "{s}\"",
            .{branch},
        );

        for (current.text) |byte| {
            switch (byte) {
                '\n' => std.debug.print(
                    "\\n",
                    .{},
                ),

                '\r' => std.debug.print(
                    "\\r",
                    .{},
                ),

                '\t' => std.debug.print(
                    "\\t",
                    .{},
                ),

                else => std.debug.print(
                    "{c}",
                    .{byte},
                ),
            }
        }

        std.debug.print(
            "\" bytes={} chars={} lines={} priority={}\n",
            .{
                current.summary.bytes,
                current.summary.chars,
                current.summary.lines,
                current.priority,
            },
        );

        self.dumpTree(
            current.left,
            depth + 1,
            .left,
        );

        self.dumpTree(
            current.right,
            depth + 1,
            .right,
        );
    }
};

// ============================================================================
// Tests
// ============================================================================

test "basic rope insertion" {
    std.debug.print(
        "\n\n============================================================\n",
        .{},
    );

    std.debug.print(
        "TEST: basic rope insertion\n",
        .{},
    );

    std.debug.print(
        "============================================================\n",
        .{},
    );

    var rope =
        Rope.init(std.testing.allocator);

    defer rope.deinit();

    try rope.insert(
        0,
        "Hello",
    );

    std.debug.print(
        "\n[1] After inserting \"Hello\":\n",
        .{},
    );

    rope.dump();

    try rope.insert(
        rope.len(),
        " world!",
    );

    std.debug.print(
        "\n[2] After inserting \" world!\":\n",
        .{},
    );

    rope.dump();

    const content =
        try rope.text(
            std.testing.allocator,
        );

    defer std.testing.allocator.free(
        content,
    );

    try std.testing.expectEqualStrings(
        "Hello world!",
        content,
    );
}

test "insert in middle" {
    std.debug.print(
        "\n\n============================================================\n",
        .{},
    );

    std.debug.print(
        "TEST: insert in middle\n",
        .{},
    );

    std.debug.print(
        "============================================================\n",
        .{},
    );

    var rope =
        Rope.init(std.testing.allocator);

    defer rope.deinit();

    try rope.insert(
        0,
        "Hello world!",
    );

    std.debug.print(
        "\n[1] Initial text:\n",
        .{},
    );

    rope.dump();

    try rope.insert(
        6,
        "beautiful ",
    );

    std.debug.print(
        "\n[2] After inserting \"beautiful \" at offset 6:\n",
        .{},
    );

    rope.dump();

    const content =
        try rope.text(
            std.testing.allocator,
        );

    defer std.testing.allocator.free(
        content,
    );

    try std.testing.expectEqualStrings(
        "Hello beautiful world!",
        content,
    );
}

test "delete" {
    std.debug.print(
        "\n\n============================================================\n",
        .{},
    );

    std.debug.print(
        "TEST: delete\n",
        .{},
    );

    std.debug.print(
        "============================================================\n",
        .{},
    );

    var rope =
        Rope.init(std.testing.allocator);

    defer rope.deinit();

    try rope.insert(
        0,
        "Hello beautiful world!",
    );

    std.debug.print(
        "\n[1] Initial text:\n",
        .{},
    );

    rope.dump();

    try rope.delete(
        6,
        10,
    );

    std.debug.print(
        "\n[2] After deleting \"beautiful \":\n",
        .{},
    );

    rope.dump();

    const content =
        try rope.text(
            std.testing.allocator,
        );

    defer std.testing.allocator.free(
        content,
    );

    try std.testing.expectEqualStrings(
        "Hello world!",
        content,
    );
}

test "replace" {
    std.debug.print(
        "\n\n============================================================\n",
        .{},
    );

    std.debug.print(
        "TEST: replace\n",
        .{},
    );

    std.debug.print(
        "============================================================\n",
        .{},
    );

    var rope =
        Rope.init(std.testing.allocator);

    defer rope.deinit();

    try rope.insert(
        0,
        "Hello world!",
    );

    std.debug.print(
        "\n[1] Initial text:\n",
        .{},
    );

    rope.dump();

    try rope.replace(
        6,
        5,
        "Zig",
    );

    std.debug.print(
        "\n[2] After replacing \"world\" with \"Zig\":\n",
        .{},
    );

    rope.dump();

    try rope.replace(
        0,
        5,
        "Goodbye",
    );

    std.debug.print(
        "\n[3] After replacing \"Hello\" with \"Goodbye\":\n",
        .{},
    );

    rope.dump();

    const content =
        try rope.text(
            std.testing.allocator,
        );

    defer std.testing.allocator.free(
        content,
    );

    try std.testing.expectEqualStrings(
        "Goodbye Zig!",
        content,
    );
}

test "line summaries" {
    std.debug.print(
        "\n\n============================================================\n",
        .{},
    );

    std.debug.print(
        "TEST: line summaries\n",
        .{},
    );

    std.debug.print(
        "============================================================\n",
        .{},
    );

    var rope =
        Rope.init(std.testing.allocator);

    defer rope.deinit();

    try rope.insert(
        0,
        "Hello\nWorld\nZig",
    );

    std.debug.print(
        "\n[1] Initial multiline text:\n",
        .{},
    );

    rope.dump();

    const summary =
        rope.summary();

    std.debug.print(
        "\nSummary details:\n",
        .{},
    );

    std.debug.print(
        "  bytes              = {}\n",
        .{summary.bytes},
    );

    std.debug.print(
        "  chars              = {}\n",
        .{summary.chars},
    );

    std.debug.print(
        "  lines              = {}\n",
        .{summary.lines},
    );

    std.debug.print(
        "  first_line_bytes   = {}\n",
        .{summary.first_line_bytes},
    );

    std.debug.print(
        "  last_line_bytes    = {}\n",
        .{summary.last_line_bytes},
    );

    std.debug.print(
        "  longest_line_bytes = {}\n",
        .{summary.longest_line_bytes},
    );

    std.debug.print(
        "  longest_line       = {}\n",
        .{summary.longest_line},
    );

    try std.testing.expectEqual(
        @as(usize, 3),
        rope.lineCount(),
    );

    try std.testing.expectEqual(
        @as(usize, 2),
        summary.lines,
    );

    try std.testing.expectEqual(
        @as(usize, 5),
        summary.first_line_bytes,
    );

    try std.testing.expectEqual(
        @as(usize, 3),
        summary.last_line_bytes,
    );
}

test "point to offset" {
    std.debug.print(
        "\n\n============================================================\n",
        .{},
    );

    std.debug.print(
        "TEST: point to offset\n",
        .{},
    );

    std.debug.print(
        "============================================================\n",
        .{},
    );

    var rope =
        Rope.init(std.testing.allocator);

    defer rope.deinit();

    try rope.insert(
        0,
        "Hello\nWorld\nZig",
    );

    std.debug.print(
        "\n[1] Rope used for point conversion:\n",
        .{},
    );

    rope.dump();

    const points = [_]Point{
        .{
            .row = 0,
            .column = 0,
        },
        .{
            .row = 0,
            .column = 5,
        },
        .{
            .row = 1,
            .column = 0,
        },
        .{
            .row = 1,
            .column = 3,
        },
        .{
            .row = 2,
            .column = 0,
        },
        .{
            .row = 2,
            .column = 3,
        },
    };

    std.debug.print(
        "\nPoint -> offset -> point:\n",
        .{},
    );

    for (points) |point| {
        const offset =
            try rope.pointToOffset(
                point,
            );

        std.debug.print(
            "  ({}, {}) -> {}\n",
            .{
                point.row,
                point.column,
                offset,
            },
        );

        const round_trip =
            try rope.offsetToPoint(
                offset,
            );

        std.debug.print(
            "      {} -> ({}, {})\n",
            .{
                offset,
                round_trip.row,
                round_trip.column,
            },
        );

        try std.testing.expectEqual(
            point.row,
            round_trip.row,
        );

        try std.testing.expectEqual(
            point.column,
            round_trip.column,
        );
    }
}

test "unicode" {
    std.debug.print(
        "\n\n============================================================\n",
        .{},
    );

    std.debug.print(
        "TEST: unicode\n",
        .{},
    );

    std.debug.print(
        "============================================================\n",
        .{},
    );

    var rope =
        Rope.init(std.testing.allocator);

    defer rope.deinit();

    try rope.insert(
        0,
        "Hello 世界 🌍!",
    );

    std.debug.print(
        "\n[1] After inserting Unicode text:\n",
        .{},
    );

    rope.dump();

    const summary =
        rope.summary();

    std.debug.print(
        "\nUTF-8 statistics:\n",
        .{},
    );

    std.debug.print(
        "  bytes = {}\n",
        .{summary.bytes},
    );

    std.debug.print(
        "  chars = {}\n",
        .{summary.chars},
    );

    try std.testing.expect(
        summary.bytes > summary.chars,
    );

    try std.testing.expect(
        rope.isCharBoundary(0),
    );

    try std.testing.expect(
        rope.isCharBoundary(
            rope.len(),
        ),
    );

    const content =
        try rope.text(
            std.testing.allocator,
        );

    defer std.testing.allocator.free(
        content,
    );

    try std.testing.expectEqualStrings(
        "Hello 世界!",
        content,
    );

    try std.testing.expect(
        std.unicode.utf8ValidateSlice(
            content,
        ),
    );

    try rope.insert(
        6,
        "beautiful ",
    );

    std.debug.print(
        "\n[2] After inserting \"beautiful \":\n",
        .{},
    );

    rope.dump();

    const final_content =
        try rope.text(
            std.testing.allocator,
        );

    defer std.testing.allocator.free(
        final_content,
    );

    try std.testing.expectEqualStrings(
        "Hello 世界 !",
        final_content,
    );
}

test "large text chunked" {
    std.debug.print(
        "\n\n============================================================\n",
        .{},
    );

    std.debug.print(
        "TEST: large text chunked\n",
        .{},
    );

    std.debug.print(
        "============================================================\n",
        .{},
    );

    var rope =
        Rope.init(std.testing.allocator);

    defer rope.deinit();

    var buffer =
        std.ArrayList(u8).empty;

    defer buffer.deinit(
        std.testing.allocator,
    );

    // Generate text substantially larger than CHUNK_SIZE.
    //
    // Zig 0.16 does not provide the old ArrayList.writer()
    // interface used by older Zig versions, so each formatted
    // line is allocated and appended explicitly.
    for (0..1000) |i| {
        const line =
            try std.fmt.allocPrint(
                std.testing.allocator,
                "Line {}\n",
                .{i},
            );

        defer std.testing.allocator.free(
            line,
        );

        try buffer.appendSlice(
            std.testing.allocator,
            line,
        );
    }

    std.debug.print(
        "\nGenerated {} bytes of text.\n",
        .{buffer.items.len},
    );

    try rope.insert(
        0,
        buffer.items,
    );

    std.debug.print(
        "\n[1] After inserting the large text:\n",
        .{},
    );

    // Don't print 1000 lines of text to the terminal.
    // The tree itself is still completely visualized.
    rope.dumpWithOptions(false);

    try std.testing.expectEqual(
        buffer.items.len,
        rope.len(),
    );

    try std.testing.expect(
        rope.len() > CHUNK_SIZE,
    );

    try std.testing.expectEqual(
        @as(usize, 1001),
        rope.lineCount(),
    );

    const content =
        try rope.text(
            std.testing.allocator,
        );

    defer std.testing.allocator.free(
        content,
    );

    try std.testing.expectEqualSlices(
        u8,
        buffer.items,
        content,
    );

    // Insert something in the middle of the large rope.
    const middle =
        rope.len() / 2;

    // Find a safe UTF-8 boundary.
    var insertion_point =
        middle;

    while (insertion_point < rope.len() and
        !rope.isCharBoundary(
            insertion_point,
        ))
    {
        insertion_point += 1;
    }

    try rope.insert(
        insertion_point,
        "[INSERTED]",
    );

    std.debug.print(
        "\n[2] After inserting \"[INSERTED]\" into the large rope:\n",
        .{},
    );

    rope.dumpWithOptions(false);

    try std.testing.expect(
        rope.len() >
            buffer.items.len,
    );

    // Verify the inserted text actually exists.
    const final_content =
        try rope.text(
            std.testing.allocator,
        );

    defer std.testing.allocator.free(
        final_content,
    );

    try std.testing.expect(
        std.mem.indexOf(
            u8,
            final_content,
            "[INSERTED]",
        ) != null,
    );
}
