const std = @import("std");
const scene_mod = @import("scene");

pub const NodeId = scene_mod.NodeId;
pub const NodeKind = scene_mod.NodeKind;
pub const Scene = scene_mod.Scene;

pub const SceneTreeError = error{
    InvalidRoot,
    TreeAlreadyActive,
    TreeNotActive,
};

pub const Error = scene_mod.SceneError ||
    std.mem.Allocator.Error ||
    SceneTreeError;

/// Manages the active portion of a Scene.
///
/// SceneTree does not own the Scene. The Scene must remain alive
/// for as long as this SceneTree uses it.
pub const SceneTree = struct {
    allocator: std.mem.Allocator,
    scene: *Scene,
    root: ?NodeId = null,

    // Nodes are stored in parent-before-child traversal order.
    // This list represents membership in the active tree.
    entered_nodes: std.ArrayList(NodeId) = .empty,

    active: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        scene: *Scene,
    ) SceneTree {
        return .{
            .allocator = allocator,
            .scene = scene,
        };
    }

    pub fn deinit(self: *SceneTree) void {
        self.entered_nodes.deinit(self.allocator);
        self.* = undefined;
    }

    // -----------------------------------------------------------------
    // Root management
    // -----------------------------------------------------------------

    /// Assigns the root node for this SceneTree.
    ///
    /// If the tree is already active, it is rebuilt around the new root.
    pub fn setRoot(
        self: *SceneTree,
        root_id: NodeId,
    ) Error!void {
        if (!self.scene.contains(root_id)) {
            return error.InvalidRoot;
        }

        if (self.root) |old_root| {
            if (old_root.eql(root_id)) return;
        }

        const was_active = self.active;

        if (was_active) {
            try self.exitTree();
        }

        self.root = root_id;

        if (was_active) {
            try self.enterTree();
        }
    }

    pub fn getRoot(self: *const SceneTree) ?NodeId {
        return self.root;
    }

    pub fn getScene(self: *SceneTree) *Scene {
        return self.scene;
    }

    pub fn isActive(self: *const SceneTree) bool {
        return self.active;
    }

    // -----------------------------------------------------------------
    // Entering and exiting the tree
    // -----------------------------------------------------------------

    /// Enters the selected root and all its descendants.
    ///
    /// Nodes are recorded in parent-before-child order.
    pub fn enterTree(self: *SceneTree) Error!void {
        if (self.active) {
            return error.TreeAlreadyActive;
        }

        const root_id = self.root orelse return error.InvalidRoot;

        if (!self.scene.contains(root_id)) {
            return error.InvalidRoot;
        }

        self.entered_nodes.clearRetainingCapacity();

        self.enterSubtree(root_id) catch |err| {
            self.entered_nodes.clearRetainingCapacity();
            return err;
        };

        self.active = true;
    }

    /// Exits the tree and clears its active membership list.
    pub fn exitTree(self: *SceneTree) SceneTreeError!void {
        if (!self.active) {
            return error.TreeNotActive;
        }

        self.active = false;
        self.entered_nodes.clearRetainingCapacity();
    }

    /// Rebuilds active membership after changes made directly to Scene.
    ///
    /// If the tree is inactive, this does nothing.
    pub fn refresh(self: *SceneTree) Error!void {
        if (!self.active) return;

        try self.exitTree();
        try self.enterTree();
    }

    fn enterSubtree(
        self: *SceneTree,
        node_id: NodeId,
    ) Error!void {
        if (!self.scene.contains(node_id)) {
            return error.InvalidHandle;
        }

        try self.entered_nodes.append(
            self.allocator,
            node_id,
        );

        const count = try self.scene.childCount(node_id);

        for (0..count) |index| {
            const child = try self.scene.childAt(node_id, index);

            if (child) |child_id| {
                try self.enterSubtree(child_id);
            }
        }
    }

    // -----------------------------------------------------------------
    // Tree membership and traversal
    // -----------------------------------------------------------------

    pub fn nodeCount(self: *const SceneTree) usize {
        if (!self.active) return 0;
        return self.entered_nodes.items.len;
    }

    /// Returns a node ID in parent-before-child traversal order.
    pub fn nodeAt(
        self: *const SceneTree,
        index: usize,
    ) ?NodeId {
        if (!self.active) return null;

        if (index >= self.entered_nodes.items.len) {
            return null;
        }

        return self.entered_nodes.items[index];
    }

    pub fn isInsideTree(
        self: *const SceneTree,
        node_id: NodeId,
    ) bool {
        if (!self.active or !self.scene.contains(node_id)) {
            return false;
        }

        for (self.entered_nodes.items) |entered_id| {
            if (entered_id.eql(node_id)) return true;
        }

        return false;
    }

    // -----------------------------------------------------------------
    // Name lookup
    // -----------------------------------------------------------------

    /// Finds the first matching node name in traversal order.
    ///
    /// Names do not have to be unique. The first match is returned.
    pub fn findNodeByName(
        self: *SceneTree,
        name: []const u8,
    ) ?NodeId {
        if (!self.active) return null;

        for (self.entered_nodes.items) |node_id| {
            const node = self.scene.getConst(node_id) catch continue;

            if (std.mem.eql(u8, node.name, name)) {
                return node_id;
            }
        }

        return null;
    }

    /// Resolves a slash-separated path from the active root.
    ///
    /// Examples:
    ///   "World/Player"
    ///   "/World/Player"
    ///   "Player"             (relative to the root)
    ///
    /// If the first path component is the root's name, it is skipped.
    pub fn findNodeByPath(
        self: *SceneTree,
        path: []const u8,
    ) Error!?NodeId {
        if (!self.active) return null;
        if (path.len == 0) return null;

        var current = self.root orelse return null;

        if (!self.scene.contains(current)) {
            return error.InvalidRoot;
        }

        var components = std.mem.tokenizeScalar(u8, path, '/');

        while (components.next()) |component| {
            const current_node = try self.scene.getConst(current);

            // Permit paths both with and without the root name.
            if (current.eql(self.root.?) and
                std.mem.eql(u8, current_node.name, component))
            {
                continue;
            }

            const count = try self.scene.childCount(current);
            var found: ?NodeId = null;

            for (0..count) |index| {
                const child = try self.scene.childAt(current, index);
                const child_id = child orelse continue;
                const child_node = try self.scene.getConst(child_id);

                if (std.mem.eql(u8, child_node.name, component)) {
                    found = child_id;
                    break;
                }
            }

            current = found orelse return null;
        }

        return current;
    }
};

// =====================================================================
// Tests
// =====================================================================

test "SceneTree initializes with a root and enters the tree" {
    var scene = try Scene.init(std.testing.allocator, "TestScene");
    defer scene.deinit();

    const root = try scene.createNode(
        null,
        "World",
        .node_2d,
    );

    var tree = SceneTree.init(std.testing.allocator, &scene);
    defer tree.deinit();

    try tree.setRoot(root);

    try std.testing.expect(!tree.isActive());
    try std.testing.expectEqual(@as(usize, 0), tree.nodeCount());

    try tree.enterTree();

    try std.testing.expect(tree.isActive());
    try std.testing.expectEqual(@as(usize, 1), tree.nodeCount());
    try std.testing.expect(tree.isInsideTree(root));
}

test "SceneTree traverses parent before children" {
    var scene = try Scene.init(std.testing.allocator, "TestScene");
    defer scene.deinit();

    const root = try scene.createNode(null, "World", .node_2d);
    const player = try scene.createNode(root, "Player", .node_2d);
    const weapon = try scene.createNode(player, "Weapon", .node_2d);
    const enemy = try scene.createNode(root, "Enemy", .node_2d);

    var tree = SceneTree.init(std.testing.allocator, &scene);
    defer tree.deinit();

    try tree.setRoot(root);
    try tree.enterTree();

    try std.testing.expectEqual(@as(usize, 4), tree.nodeCount());

    try std.testing.expect(tree.nodeAt(0).?.eql(root));
    try std.testing.expect(tree.nodeAt(1).?.eql(player));
    try std.testing.expect(tree.nodeAt(2).?.eql(weapon));
    try std.testing.expect(tree.nodeAt(3).?.eql(enemy));

    try std.testing.expect(tree.nodeAt(4) == null);
}

test "SceneTree exits and re-enters cleanly" {
    var scene = try Scene.init(std.testing.allocator, "TestScene");
    defer scene.deinit();

    const root = try scene.createNode(null, "World", .node_2d);
    const child = try scene.createNode(root, "Player", .node_2d);

    var tree = SceneTree.init(std.testing.allocator, &scene);
    defer tree.deinit();

    try tree.setRoot(root);
    try tree.enterTree();

    try std.testing.expect(tree.isInsideTree(child));

    try tree.exitTree();

    try std.testing.expect(!tree.isActive());
    try std.testing.expect(!tree.isInsideTree(child));
    try std.testing.expectEqual(@as(usize, 0), tree.nodeCount());

    try tree.enterTree();

    try std.testing.expect(tree.isInsideTree(child));
    try std.testing.expectEqual(@as(usize, 2), tree.nodeCount());
}

test "SceneTree rejects invalid lifecycle transitions" {
    var scene = try Scene.init(std.testing.allocator, "TestScene");
    defer scene.deinit();

    const root = try scene.createNode(null, "World", .node_2d);

    var tree = SceneTree.init(std.testing.allocator, &scene);
    defer tree.deinit();

    try std.testing.expectError(error.InvalidRoot, tree.enterTree());

    try tree.setRoot(root);
    try tree.enterTree();

    try std.testing.expectError(error.TreeAlreadyActive, tree.enterTree());

    try tree.exitTree();

    try std.testing.expectError(error.TreeNotActive, tree.exitTree());
}

test "SceneTree finds nodes by name" {
    var scene = try Scene.init(std.testing.allocator, "TestScene");
    defer scene.deinit();

    const root = try scene.createNode(null, "World", .node_2d);
    const player = try scene.createNode(root, "Player", .node_2d);
    _ = try scene.createNode(root, "Enemy", .node_2d);

    var tree = SceneTree.init(std.testing.allocator, &scene);
    defer tree.deinit();

    try tree.setRoot(root);

    // Lookup is restricted to active trees.
    try std.testing.expect(tree.findNodeByName("Player") == null);

    try tree.enterTree();

    const found = tree.findNodeByName("Player");
    try std.testing.expect(found != null);
    try std.testing.expect(found.?.eql(player));

    try std.testing.expect(tree.findNodeByName("Missing") == null);
}

test "SceneTree resolves node paths" {
    var scene = try Scene.init(std.testing.allocator, "TestScene");
    defer scene.deinit();

    const root = try scene.createNode(null, "World", .node_2d);
    const player = try scene.createNode(root, "Player", .node_2d);
    const weapon = try scene.createNode(player, "Weapon", .node_2d);

    var tree = SceneTree.init(std.testing.allocator, &scene);
    defer tree.deinit();

    try tree.setRoot(root);
    try tree.enterTree();

    const path_a = (try tree.findNodeByPath("World/Player/Weapon")).?;
    const path_b = (try tree.findNodeByPath("/World/Player/Weapon")).?;
    const path_c = (try tree.findNodeByPath("Player/Weapon")).?;

    try std.testing.expect(path_a.eql(weapon));
    try std.testing.expect(path_b.eql(weapon));
    try std.testing.expect(path_c.eql(weapon));

    try std.testing.expect(
        (try tree.findNodeByPath("World/Missing")) == null,
    );
}

test "SceneTree can change its root while active" {
    var scene = try Scene.init(std.testing.allocator, "TestScene");
    defer scene.deinit();

    const root_a = try scene.createNode(null, "WorldA", .node_2d);
    const root_b = try scene.createNode(null, "WorldB", .node_2d);
    const child_a = try scene.createNode(root_a, "PlayerA", .node_2d);
    const child_b = try scene.createNode(root_b, "PlayerB", .node_2d);

    var tree = SceneTree.init(std.testing.allocator, &scene);
    defer tree.deinit();

    try tree.setRoot(root_a);
    try tree.enterTree();

    try std.testing.expect(tree.isInsideTree(child_a));
    try std.testing.expect(!tree.isInsideTree(child_b));

    try tree.setRoot(root_b);

    try std.testing.expect(tree.isActive());
    try std.testing.expect(!tree.isInsideTree(child_a));
    try std.testing.expect(tree.isInsideTree(child_b));
    try std.testing.expectEqual(@as(usize, 2), tree.nodeCount());
}

test "SceneTree refreshes after direct scene mutations" {
    var scene = try Scene.init(std.testing.allocator, "TestScene");
    defer scene.deinit();

    const root = try scene.createNode(null, "World", .node_2d);

    var tree = SceneTree.init(std.testing.allocator, &scene);
    defer tree.deinit();

    try tree.setRoot(root);
    try tree.enterTree();

    const child = try scene.createNode(root, "Player", .node_2d);

    // Direct edits to Scene require a refresh to update tree membership.
    try std.testing.expect(!tree.isInsideTree(child));

    try tree.refresh();

    try std.testing.expect(tree.isInsideTree(child));
    try std.testing.expectEqual(@as(usize, 2), tree.nodeCount());
}
