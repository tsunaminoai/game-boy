const std = @import("std");

pub const Device = @import("device.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
