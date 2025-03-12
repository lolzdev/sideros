const std = @import("std");
pub const tan = std.math.tan;
pub const cos = std.math.cos;
pub const sin = std.math.sin;
pub const rad = std.math.degreesToRadians;

pub const Matrix = struct {
    rows: [4]@Vector(4, f32),

    pub fn lookAt(eye: @Vector(3, f32), target: @Vector(3, f32), arbitrary_up: @Vector(3, f32)) Matrix {
        const forward = normalize(eye - target);
        const right = normalize(cross(arbitrary_up, forward));
        const up = cross(forward, right);

        const view = [_]@Vector(4, f32){
            @Vector(4, f32){ right[0], right[1], right[2], 0.0 },
            @Vector(4, f32){ up[0], up[1], up[2], 0.0 },
            @Vector(4, f32){ forward[0], forward[1], forward[2], 0.0 },
            @Vector(4, f32){ 0.0, 0.0, 1.0, eye[2] },
        };

        return Matrix{
            .rows = view,
        };
    }

    pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) Matrix {
        const projection = [_]@Vector(4, f32){
            @Vector(4, f32){ 1.0 / (aspect * tan(fov / 2.0)), 0.0, 0.0, 0.0 },
            @Vector(4, f32){ 0.0, 1.0 / tan(fov / 2.0), 0.0, 0.0 },
            @Vector(4, f32){ 0.0, 0.0, -((far + near) / (far - near)), -((2 * far * near) / (far - near)) },
            @Vector(4, f32){ 0.0, 0.0, -1.0, 1.0 },
        };

        return Matrix{
            .rows = projection,
        };
    }

    pub fn identity() Matrix {
        const view = [_]@Vector(4, f32){
            @Vector(4, f32){ 1.0, 0.0, 0.0, 0.0 },
            @Vector(4, f32){ 0.0, 1.0, 0.0, 0.0 },
            @Vector(4, f32){ 0.0, 0.0, 1.0, 0.0 },
            @Vector(4, f32){ 0.0, 0.0, 0.0, 1.0 },
        };

        return Matrix{
            .rows = view,
        };
    }
};

pub fn dot(a: @Vector(3, f32), b: @Vector(3, f32)) f32 {
    return @reduce(.Add, a * b);
}

pub fn cross(a: @Vector(3, f32), b: @Vector(3, f32)) @Vector(3, f32) {
    return @Vector(3, f32){ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

pub fn normalize(a: @Vector(3, f32)) @Vector(3, f32) {
    return a / @as(@Vector(3, f32), @splat(@sqrt(dot(a, a))));
}
