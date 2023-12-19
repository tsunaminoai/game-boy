const std = @import("std");
const GB = @import("gameboy");

// TODO: make a real loader thats not loading only 256B
fn loadProgram(path: []const u8, cpu: *GB.LR35902.CPU()) !void {
    std.log.debug("Loading '{s}'\n", .{path});

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

fn fatal(err: anyerror, cpu: *GB.LR35902.CPU()) !noreturn {
    var STDOUT = std.io.getStdOut();
    var stdout = STDOUT.writer();
    try stdout.print("Fatal error: {s}\n", .{@errorName(err)});
    try stdout.print("Registers:\n{s}\n", .{cpu.registers});
    // try stdout.print("Stack:\n{s}\n", .{cpu.stack});
    var mem = try cpu.ram.getDevice(0x8000);
    try stdout.print("Memory:\n{}\n", .{mem.?});
    std.os.exit(1);
}

/// main function
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var cpu = try GB.LR35902.CPU().init(allocator);
    try loadProgram("rom.bin", &cpu);
    for (0..10_000_000) |_| {
        cpu.tick() catch |err| {
            try fatal(err, &cpu);
        };
    }

    var STDOUT = std.io.getStdOut();
    var stdout = STDOUT.writer();
    try stdout.print("Registers:\n{s}\n", .{cpu.registers});
    var mem = try cpu.ram.getDevice(0x8000);

    try stdout.print("Memory:\n{}\n", .{mem.?});
}

test {
    std.testing.refAllDecls(@This());
}
