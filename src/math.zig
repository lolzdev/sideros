const std = @import("std");
pub const tan = std.math.tan;
pub const cos = std.math.cos;
pub const sin = std.math.sin;
pub const rad = std.math.degreesToRadians;
pub const sqrt = std.math.sqrt;

pub const Axis = struct {
    pub const x: [3]f32 = .{1.0, 0.0, 0.0};
    pub const y: [3]f32 = .{0.0, 1.0, 0.0};
    pub const z: [3]f32 = .{0.0, 0.0, 1.0};
};

pub const Transform = struct {
    translation: Matrix,
    scale: Matrix,
    rotation: Quaternion,

    pub fn init(position: [3]f32, scale: [3]f32, rotation: [3]f32) Transform {
        var translation = Matrix.identity();
        translation.translate(position);

        return .{
            .translation = translation,
            .rotation = Quaternion.fromEulerAngles(rotation),
            .scale = Matrix.scale(scale),
        };
    }

    pub fn translate(self: *Transform, delta: [3]f32) void {
        self.translation.translate(delta);
    }

    pub fn rotate(self: *Transform, angle: f32, axis: [3]f32) void {
        const delta = Quaternion.fromAxisAngle(axis, angle);
        self.rotation = self.rotation.mul(delta);
        self.rotation = self.rotation.normalize();
    }
};

pub const Matrix = struct {
    rows: [4][4]f32,

    pub fn lookAt(eye: [3]f32, target: [3]f32, arbitrary_up: [3]f32) Matrix {
        const t: @Vector(3, f32) = target;
        const e: @Vector(3, f32) = eye;
        const u: @Vector(3, f32) = arbitrary_up;
        const forward = normalize(t - e);
        const right = normalize(cross(forward, u));
        const up = cross(right, forward);

        const view = [4][4]f32{
            [4]f32{ right[0], up[0], -forward[0], 0.0 },
            [4]f32{ right[1], up[1], -forward[1], 0.0 },
            [4]f32{ right[2], up[2], -forward[2], 0.0 },
            [4]f32{ -dot(e, right), -dot(e, up), -dot(e, forward), 1.0 },
        };

        return .{
            .rows = view,
        };
    }

    pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) Matrix {
        const focal_length = 1.0 / tan(fov / 2.0);
        const x = focal_length / aspect;
        const y = -focal_length;
        const a = near / (far - near);
        const b = far * a;

        const projection = [4][4]f32{
            [4]f32{ x, 0.0, 0.0, 0.0 },
            [4]f32{ 0.0, y, 0.0, 0.0 },
            [4]f32{ 0.0, 0.0, a, b },
            [4]f32{ 0.0, 0.0, 1.0, 0.0 },
        };

        return .{
            .rows = projection,
        };
    }

    pub inline fn identity() Matrix {
        return .{
            .rows = .{
                [4]f32{ 1.0, 0.0, 0.0, 0.0 },
                [4]f32{ 0.0, 1.0, 0.0, 0.0 },
                [4]f32{ 0.0, 0.0, 1.0, 0.0 },
                [4]f32{ 0.0, 0.0, 0.0, 1.0 },
            },
        };
    }

    pub fn mul(a: Matrix, b: Matrix) Matrix {
        var result = [4][4]f32{
            [4]f32{ 0.0, 0.0, 0.0, 0.0 },
            [4]f32{ 0.0, 0.0, 0.0, 0.0 },
            [4]f32{ 0.0, 0.0, 0.0, 0.0 },
            [4]f32{ 0.0, 0.0, 0.0, 0.0 },
        };

        for (0..4) |i| {
            for (0..4) |j| {
                for (0..4) |k| {
                    result[i][j] += a.rows[i][k] * b.rows[k][j];
                }
            }
        }

        return .{
            .rows = result,
        };
    }

    pub inline fn translate(a: *Matrix, pos: [3]f32) void {
        a.rows[3][0] += pos[0];
        a.rows[3][1] += pos[1];
        a.rows[3][2] += pos[2];
    }

    pub inline fn scale(s: [3]f32) Matrix {
        return .{
            .rows = [4][4]f32{
                [4]f32{ s[0], 0.0, 0.0, 0.0 },
                [4]f32{ 0.0, s[1], 0.0, 0.0 },
                [4]f32{ 0.0, 0.0, s[2], 0.0 },
                [4]f32{ 0.0, 0.0, 0.0, 1.0 },
            },
        };
    }

    pub fn transform(pos: [3]f32, s: [3]f32) Matrix {
        var translation = Matrix.identity();
        translation.translate(pos);

        return translation.mul(Matrix.scale(s));
    }
};

const Quaternion = struct {
    w: f32,
    x: f32,
    y: f32,
    z: f32,

    pub const identity: Quaternion = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 };

    pub fn fromAxisAngle(axis: [3]f32, angle: f32) Quaternion {
        const half_angle = angle / 2.0;
        const s = sin(half_angle);

        return .{
            .w = cos(half_angle),
            .x = axis[0] * s,
            .y = axis[1] * s,
            .z = axis[3] * s,
        };
    }

    fn fromEulerAngles(rotation: [3]f32) Quaternion {
        const pitch = rotation[0];
        const yaw = rotation[1];
        const roll = rotation[2];

        const half_pitch = pitch / 2.0;
        const half_yaw = yaw / 2.0;
        const half_roll = roll / 2.0;

        const sin_pitch = sin(half_pitch);
        const cos_pitch = cos(half_pitch);
        const sin_yaw = sin(half_yaw);
        const cos_yaw = cos(half_yaw);
        const sin_roll = sin(half_roll);
        const cos_roll = cos(half_roll);

        return .{
            .w = cos_yaw * cos_pitch * cos_roll + sin_yaw * sin_pitch * sin_roll,
            .x = cos_yaw * sin_pitch * cos_roll + sin_yaw * cos_pitch * sin_roll,
            .y = sin_yaw * cos_pitch * cos_roll - cos_yaw * sin_pitch * sin_roll,
            .z = cos_yaw * cos_pitch * sin_roll - sin_yaw * sin_pitch * cos_roll,
        };
    }


    inline fn mul(a: Quaternion, b: Quaternion) Quaternion {
        return .{
            .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
            .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        };
    }

    fn normalize(q: Quaternion) Quaternion {
        const mag = sqrt(q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z);
        return Quaternion{
            .w = q.w / mag,
            .x = q.x / mag,
            .y = q.y / mag,
            .z = q.z / mag,
        };
    }

    fn matrix(q: Quaternion) Matrix {
        const x2 = q.x + q.x;
        const y2 = q.y + q.y;
        const z2 = q.z + q.z;

        const xx = q.x * x2;
        const yy = q.y * y2;
        const zz = q.z * z2;
        const xy = q.x * y2;
        const xz = q.x * z2;
        const yz = q.y * z2;
        const wx = q.w * x2;
        const wy = q.w * y2;
        const wz = q.w * z2;

        return .{
            .rows = .{
                .{ 1.0 - (yy + zz), xy - wz, xz + wy, 0.0 },
                .{ xy + wz, 1.0 - (xx + zz), yz - wx, 0.0 },
                .{ xz - wy, yz + wx, 1.0 - (xx + yy), 0.0 },
                .{ 0.0, 0.0, 0.0, 1.0 },
            }
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
