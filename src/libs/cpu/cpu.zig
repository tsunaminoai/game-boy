const std = @import("std");
pub const LR35902 = @import("LR35902.zig");
pub const MMU = @import("mmu.zig");
pub const Bus = @import("bus.zig");
pub const Register = @import("register.zig");
pub const Opcodes = @import("opcodes.zig");

pub usingnamespace LR35902;
pub usingnamespace MMU;
pub usingnamespace Bus;
pub usingnamespace Register;
pub usingnamespace Opcodes;

test {
    std.testing.refAllDeclsRecursive(@This());
}
