const std = @import("std");

const gravity: f16 = 9.8;

pub const Vec2 = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,

    pub fn init(x: f64, y: f64) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn scale(a: Vec2, s: f64) Vec2 {
        return .{ .x = a.x * s, .y = a.y * s };
    }

    pub fn dot(a: Vec2, b: Vec2) f64 {
        return a.x * b.x + a.y * b.y;
    }

    pub fn lengthSq(a: Vec2) f64 {
        return Vec2.dot(a, a);
    }

    pub fn length(a: Vec2) f64 {
        return std.math.sqrt(Vec2.lengthSq(a));
    }

    pub fn normalized(a: Vec2) Vec2 {
        const len = Vec2.length(a);
        if (len <= 1e-12) return .{ .x = 1.0, .y = 0.0 };
        return .{ .x = a.x / len, .y = a.y / len };
    }
};
