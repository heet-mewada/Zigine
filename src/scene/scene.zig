const std = @import("std");

pub const SceneError = error{
    InvalidHandle,
    InvalidParent,
    HierarchyCycle,
    EmptyName,
    TooManyNodes,
    InvalidTransform,
    InvalidScale,
};

pub const NodeId = struct {
    index: u32,
    generation: u32,

    pub fn eql(a: NodeId, b: NodeId) bool {
        return a.index == b.index and
            a.generation == b.generation;
    }
};

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Transform2D = struct {
    position: Vec2 = .{},
    rotation: f32 = 0,
    scale: Vec2 = .{ .x = 1, .y = 1 },

    pub fn toAffine(self: Transform2D) Affine2D {
        const cosine = @cos(self.rotation);
        const sine = @sin(self.rotation);

        return .{
            .a = cosine * self.scale.x,
            .b = sine * self.scale.x,
            .c = -sine * self.scale.y,
            .d = cosine * self.scale.y,
            .tx = self.position.x,
            .ty = self.position.y,
        };
    }
};

/// A 2D affine transformation.
///
/// x' = a*x + c*y + tx
/// y' = b*x + d*y + ty
pub const Affine2D = struct {
    a: f32 = 1,
    b: f32 = 0,
    c: f32 = 0,
    d: f32 = 1,
    tx: f32 = 0,
    ty: f32 = 0,

    /// Returns the transformation produced by applying `local`
    /// in the coordinate space described by `self`.
    pub fn multiply(self: Affine2D, local: Affine2D) Affine2D {
        return .{
            .a = self.a * local.a + self.c * local.b,
            .b = self.b * local.a + self.d * local.b,
            .c = self.a * local.c + self.c * local.d,
            .d = self.b * local.c + self.d * local.d,
            .tx = self.a * local.tx +
                self.c * local.ty + self.tx,
            .ty = self.b * local.tx +
                self.d * local.ty + self.ty,
        };
    }

    pub fn transformPoint(
        self: Affine2D,
        point: Vec2,
    ) Vec2 {
        return .{
            .x = self.a * point.x +
                self.c * point.y + self.tx,
            .y = self.b * point.x +
                self.d * point.y + self.ty,
        };
    }

    pub fn inverseTransformPoint(self: Affine2D, point: Vec2) ?Vec2 {
        const determinant = self.a * self.d - self.b * self.c;
        if (!std.math.isFinite(determinant) or @abs(determinant) < 0.000001) return null;
        const x = point.x - self.tx;
        const y = point.y - self.ty;
        return .{
            .x = (self.d * x - self.c * y) / determinant,
            .y = (-self.b * x + self.a * y) / determinant,
        };
    }
};

pub const NodeKind = enum {
    node,
    node_2d,
    sprite_2d,
    camera_2d,
};

/// Initial common representation for built-in scene nodes.
///
/// The transform is meaningful for 2D node kinds. A later version
/// can separate non-spatial Node data from Node2D data more strictly.
pub const Node = struct {
    id: NodeId,
    name: []u8,
    kind: NodeKind,
    parent: ?NodeId = null,
    transform: Transform2D = .{},
    visible: bool = true,

    /// Resource path used by Sprite2D in this initial implementation.
    /// Resource ownership and loading will be implemented separately.
    texture_path: ?[]u8 = null,
};

const Slot = struct {
    generation: u32 = 1,
    alive: bool = true,
    node: Node,
};

/// Owns a scene's nodes and their names.
///
/// Child lists are derived from parent IDs in this first version.
/// This keeps reparenting simple and avoids maintaining two sources
/// of truth for parent-child relationships.
pub const Scene = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    slots: std.ArrayList(Slot) = .empty,

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
    ) !Scene {
        if (name.len == 0) return error.EmptyName;

        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
        };
    }

    pub fn deinit(self: *Scene) void {
        for (self.slots.items) |*slot| {
            if (slot.alive) {
                self.destroyNodeData(&slot.node);
                slot.alive = false;
            }
        }

        self.slots.deinit(self.allocator);
        self.allocator.free(self.name);
        self.* = undefined;
    }

    fn destroyNodeData(
        self: *Scene,
        node: *Node,
    ) void {
        self.allocator.free(node.name);

        if (node.texture_path) |path| {
            self.allocator.free(path);
        }

        node.name = &.{};
        node.texture_path = null;
    }

    fn validId(self: *const Scene, id: NodeId) bool {
        const index: usize = id.index;

        if (index >= self.slots.items.len) {
            return false;
        }

        const slot = &self.slots.items[index];

        return slot.alive and
            slot.generation == id.generation;
    }

    pub fn get(
        self: *Scene,
        id: NodeId,
    ) SceneError!*Node {
        if (!self.validId(id)) {
            return error.InvalidHandle;
        }

        return &self.slots.items[id.index].node;
    }

    pub fn getConst(
        self: *const Scene,
        id: NodeId,
    ) SceneError!*const Node {
        if (!self.validId(id)) {
            return error.InvalidHandle;
        }

        return &self.slots.items[id.index].node;
    }

    pub fn contains(
        self: *const Scene,
        id: NodeId,
    ) bool {
        return self.validId(id);
    }

    pub fn nodeCount(self: *const Scene) usize {
        var count: usize = 0;

        for (self.slots.items) |slot| {
            if (slot.alive) count += 1;
        }

        return count;
    }

    pub fn createNode(
        self: *Scene,
        parent: ?NodeId,
        name: []const u8,
        kind: NodeKind,
    ) (SceneError || std.mem.Allocator.Error)!NodeId {
        if (name.len == 0) return error.EmptyName;

        if (parent) |parent_id| {
            if (!self.validId(parent_id)) {
                return error.InvalidParent;
            }
        }

        if (self.slots.items.len >= std.math.maxInt(u32)) {
            return error.TooManyNodes;
        }

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        const index: u32 = @intCast(self.slots.items.len);
        const id = NodeId{
            .index = index,
            .generation = 1,
        };

        try self.slots.append(self.allocator, .{
            .generation = id.generation,
            .alive = true,
            .node = .{
                .id = id,
                .name = owned_name,
                .kind = kind,
                .parent = parent,
            },
        });

        return id;
    }

    pub fn renameNode(
        self: *Scene,
        id: NodeId,
        new_name: []const u8,
    ) (SceneError || std.mem.Allocator.Error)!void {
        if (new_name.len == 0) return error.EmptyName;

        const node = try self.get(id);
        const owned_name = try self.allocator.dupe(u8, new_name);

        self.allocator.free(node.name);
        node.name = owned_name;
    }

    /// Replaces a Sprite2D texture path. An empty path clears the texture.
    /// The scene owns the stored path, so callers may release their input
    /// immediately after this method returns.
    pub fn setTexturePath(
        self: *Scene,
        id: NodeId,
        path: []const u8,
    ) (SceneError || std.mem.Allocator.Error)!void {
        const node = try self.get(id);

        const owned_path: ?[]u8 = if (path.len == 0)
            null
        else
            try self.allocator.dupe(u8, path);
        errdefer if (owned_path) |value| self.allocator.free(value);

        if (node.texture_path) |old_path| {
            self.allocator.free(old_path);
        }
        node.texture_path = owned_path;
    }

    pub fn setVisible(
        self: *Scene,
        id: NodeId,
        visible: bool,
    ) SceneError!void {
        const node = try self.get(id);
        node.visible = visible;
    }

    /// Reparents a node. Passing null makes it a root node.
    ///
    /// This rejects self-parenting and cycles. It does not preserve
    /// the node's global transform yet; that will be a separate,
    /// explicit editor operation.
    pub fn reparent(
        self: *Scene,
        id: NodeId,
        new_parent: ?NodeId,
    ) SceneError!void {
        const node = try self.get(id);

        if (new_parent) |parent_id| {
            if (!self.validId(parent_id)) {
                return error.InvalidParent;
            }

            if (id.eql(parent_id)) {
                return error.HierarchyCycle;
            }

            var cursor: ?NodeId = parent_id;

            while (cursor) |ancestor_id| {
                if (id.eql(ancestor_id)) {
                    return error.HierarchyCycle;
                }

                const ancestor = try self.get(ancestor_id);
                cursor = ancestor.parent;
            }
        }

        node.parent = new_parent;
    }

    /// Returns the number of direct children of `parent`.
    pub fn childCount(
        self: *const Scene,
        parent: NodeId,
    ) SceneError!usize {
        if (!self.validId(parent)) {
            return error.InvalidHandle;
        }

        var count: usize = 0;

        for (self.slots.items) |slot| {
            if (!slot.alive) continue;

            if (slot.node.parent) |parent_id| {
                if (parent_id.eql(parent)) {
                    count += 1;
                }
            }
        }

        return count;
    }

    /// Returns the direct child at `child_index`, in creation order.
    /// Returns null when the index is out of range.
    pub fn childAt(
        self: *const Scene,
        parent: NodeId,
        child_index: usize,
    ) SceneError!?NodeId {
        if (!self.validId(parent)) {
            return error.InvalidHandle;
        }

        var current: usize = 0;

        for (self.slots.items) |slot| {
            if (!slot.alive) continue;

            if (slot.node.parent) |parent_id| {
                if (parent_id.eql(parent)) {
                    if (current == child_index) {
                        return slot.node.id;
                    }

                    current += 1;
                }
            }
        }

        return null;
    }

    /// Returns a root node at the given root index.
    pub fn rootAt(
        self: *const Scene,
        root_index: usize,
    ) ?NodeId {
        var current: usize = 0;

        for (self.slots.items) |slot| {
            if (!slot.alive) continue;
            if (slot.node.parent != null) continue;

            if (current == root_index) {
                return slot.node.id;
            }

            current += 1;
        }

        return null;
    }

    fn firstChild(
        self: *const Scene,
        parent: NodeId,
    ) ?NodeId {
        for (self.slots.items) |slot| {
            if (!slot.alive) continue;

            if (slot.node.parent) |parent_id| {
                if (parent_id.eql(parent)) {
                    return slot.node.id;
                }
            }
        }

        return null;
    }

    /// Removes a node and its entire subtree.
    ///
    /// The slots are invalidated, not reused. Existing handles therefore
    /// cannot silently start referring to newly created nodes.
    pub fn removeNode(
        self: *Scene,
        id: NodeId,
    ) SceneError!void {
        _ = try self.get(id);

        while (self.firstChild(id)) |child_id| {
            try self.removeNode(child_id);
        }

        const slot = &self.slots.items[id.index];

        self.destroyNodeData(&slot.node);
        slot.alive = false;

        // Incrementing also invalidates the old generation explicitly.
        slot.generation +%= 1;
    }

    pub fn setTransform(
        self: *Scene,
        id: NodeId,
        transform: Transform2D,
    ) SceneError!void {
        const node = try self.get(id);
        if (!std.math.isFinite(transform.position.x) or
            !std.math.isFinite(transform.position.y) or
            !std.math.isFinite(transform.rotation) or
            !std.math.isFinite(transform.scale.x) or
            !std.math.isFinite(transform.scale.y)) return error.InvalidTransform;
        if (transform.scale.x < 0 or transform.scale.y < 0) {
            return error.InvalidScale;
        }
        node.transform = transform;
    }

    /// Calculates the node's global transform by composing its local
    /// transform with every ancestor's global transform.
    ///
    /// This is intentionally computed on demand in Phase 1.
    /// A cached transform system can be added after the model is stable.
    pub fn globalTransform(
        self: *Scene,
        id: NodeId,
    ) SceneError!Affine2D {
        const node = try self.get(id);
        const local = node.transform.toAffine();

        if (node.parent) |parent_id| {
            const parent_global = try self.globalTransform(parent_id);
            return parent_global.multiply(local);
        }

        return local;
    }
};

test "create nodes and enumerate children" {
    var scene = try Scene.init(
        std.testing.allocator,
        "Main",
    );
    defer scene.deinit();

    const root = try scene.createNode(
        null,
        "Main",
        .node_2d,
    );

    const player = try scene.createNode(
        root,
        "Player",
        .sprite_2d,
    );

    _ = try scene.createNode(
        root,
        "Camera",
        .camera_2d,
    );

    try std.testing.expectEqual(@as(usize, 3), scene.nodeCount());
    try std.testing.expectEqual(@as(usize, 2), try scene.childCount(root));

    const first = (try scene.childAt(root, 0)).?;
    try std.testing.expect(first.eql(player));

    try std.testing.expect(scene.contains(player));
}

test "rename a node" {
    var scene = try Scene.init(
        std.testing.allocator,
        "Main",
    );
    defer scene.deinit();

    const node_id = try scene.createNode(
        null,
        "OldName",
        .node_2d,
    );

    try scene.renameNode(node_id, "Player");

    const node = try scene.getConst(node_id);
    try std.testing.expectEqualStrings("Player", node.name);
}

test "Sprite2D texture path is owned and can be cleared" {
    var scene = try Scene.init(std.testing.allocator, "Main");
    defer scene.deinit();

    const sprite = try scene.createNode(null, "Sprite", .sprite_2d);
    try scene.setTexturePath(sprite, "assets/player.png");

    var path = try std.testing.allocator.dupe(u8, "assets/enemy.png");
    defer std.testing.allocator.free(path);
    try scene.setTexturePath(sprite, path);
    path[7] = 'X';

    const assigned = try scene.getConst(sprite);
    try std.testing.expectEqualStrings("assets/enemy.png", assigned.texture_path.?);

    try scene.setTexturePath(sprite, "");
    try std.testing.expect((try scene.getConst(sprite)).texture_path == null);
}

test "reparent nodes and reject cycles" {
    var scene = try Scene.init(
        std.testing.allocator,
        "Main",
    );
    defer scene.deinit();

    const root = try scene.createNode(null, "Root", .node_2d);
    const child = try scene.createNode(root, "Child", .node_2d);
    const grandchild = try scene.createNode(child, "Grandchild", .node_2d);

    try std.testing.expectError(
        error.HierarchyCycle,
        scene.reparent(root, grandchild),
    );

    try std.testing.expectError(
        error.HierarchyCycle,
        scene.reparent(child, child),
    );

    try scene.reparent(grandchild, root);

    const updated = try scene.getConst(grandchild);
    try std.testing.expect(updated.parent.?.eql(root));
}

test "removing a node removes its descendants and invalidates handles" {
    var scene = try Scene.init(
        std.testing.allocator,
        "Main",
    );
    defer scene.deinit();

    const root = try scene.createNode(null, "Root", .node_2d);
    const child = try scene.createNode(root, "Child", .node_2d);
    const grandchild = try scene.createNode(child, "Grandchild", .node_2d);

    try scene.removeNode(child);

    try std.testing.expect(scene.contains(root));
    try std.testing.expect(!scene.contains(child));
    try std.testing.expect(!scene.contains(grandchild));
    try std.testing.expectEqual(@as(usize, 1), scene.nodeCount());

    try std.testing.expectError(
        error.InvalidHandle,
        scene.get(child),
    );
}

test "global transform includes parent translation" {
    var scene = try Scene.init(
        std.testing.allocator,
        "Main",
    );
    defer scene.deinit();

    const parent = try scene.createNode(null, "Parent", .node_2d);
    const child = try scene.createNode(parent, "Child", .node_2d);

    try scene.setTransform(parent, .{
        .position = .{ .x = 100, .y = 50 },
    });

    try scene.setTransform(child, .{
        .position = .{ .x = 10, .y = 20 },
    });

    const global = try scene.globalTransform(child);
    const origin = global.transformPoint(.{});

    try std.testing.expectApproxEqAbs(@as(f32, 110), origin.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 70), origin.y, 0.001);
}

test "inverse affine transform maps world point back to local point" {
    const local_transform = Transform2D{
        .position = .{ .x = 100, .y = 50 },
        .rotation = std.math.pi / 2,
        .scale = .{ .x = 2, .y = 3 },
    };
    const transform = local_transform.toAffine();
    const world = transform.transformPoint(.{ .x = 4, .y = 5 });
    const local = transform.inverseTransformPoint(world).?;
    try std.testing.expectApproxEqAbs(@as(f32, 4), local.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5), local.y, 0.001);
}

test "negative node scales are rejected" {
    var scene = try Scene.init(std.testing.allocator, "Main");
    defer scene.deinit();

    const node = try scene.createNode(null, "Node", .node_2d);
    try std.testing.expectError(
        error.InvalidScale,
        scene.setTransform(node, .{ .scale = .{ .x = -1, .y = 1 } }),
    );
}

test "reparenting to null makes a node a root" {
    var scene = try Scene.init(
        std.testing.allocator,
        "Main",
    );
    defer scene.deinit();

    const root = try scene.createNode(null, "Root", .node_2d);
    const child = try scene.createNode(root, "Child", .node_2d);

    try scene.reparent(child, null);

    const node = try scene.getConst(child);
    try std.testing.expect(node.parent == null);
    try std.testing.expect(scene.rootAt(1).?.eql(child));
}
