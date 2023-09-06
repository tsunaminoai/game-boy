const std = @import("std");
const CPU = @import("./libs/cpu/cpu.zig").CPU;

fn loadProgram(path: []const u8, cpu: *CPU) !void {
    std.debug.print("Loading '{s}'", .{path});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 64000);
    defer allocator.free(data);

    var i: u16 = 0;
    while ( i < data.len) : (i += 1 ) {
        cpu.WriteMemory(i, @as(u16, data[i]), 1);
    }
}

/// main function
pub fn main() !void {
    var cpu = CPU{};
    try loadProgram("rom.bin", &cpu);
    try cpu.Run();
    cpu.dump("Final State");
}

test {
    std.testing.refAllDecls(@This());
}
