const std = @import("std");
const GB = @import("gameboy");

// TODO: make a real loader thats not loading only 256B
fn loadProgram(path: []const u8, cpu: *GB.CPU()) !void {
    std.debug.print("Loading '{s}'\n", .{path});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 64000);
    defer allocator.free(data);

    var i: u16 = 0;
    while (i < data.len) : (i += 1) {
        try cpu.ram.write(i, 1, data[i]);
        if (i > 256) break;
    }
}

/// main function
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var cpu = try GB.CPU().init(allocator);
    try loadProgram("rom.bin", &cpu);
    for (0..1000) |_| try cpu.tick();

    var STDOUT = std.io.getStdOut();
    var stdout = STDOUT.writer();
    try stdout.print("Registers:\n{s}\n", .{cpu.registers});
}

test {
    std.testing.refAllDecls(@This());
}
