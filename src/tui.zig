const std = @import("std");
const Array = std.ArrayList;
const Allocator = std.mem.Allocator;
const tst = std.testing;
const math = std.math;
const vaxis = @import("vaxis");
const log = std.log.scoped(.main);

const View = vaxis.widgets.View;
const Cell = vaxis.Cell;
const border = vaxis.widgets.border;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            log.err("memory leak", .{});
        }
    }
    const alloc = gpa.allocator();

    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    var buffered_writer = tty.bufferedWriter();
    const writer = buffered_writer.writer().any();

    // Initialize Vaxis
    var vx = try vaxis.init(alloc, .{
        .kitty_keyboard_flags = .{ .report_events = true },
    });
    defer vx.deinit(alloc, tty.anyWriter());
    var loop: vaxis.Loop(Event) = .{
        .vaxis = &vx,
        .tty = &tty,
    };
    try loop.init();
    try loop.start();
    defer loop.stop();
    try vx.enterAltScreen(writer);
    try buffered_writer.flush();
    try vx.queryTerminal(tty.anyWriter(), 20 * std.time.ns_per_s);
    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) break;
            },
            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
        }

        const win = vx.window();
        win.clear();

        const controls_win = win.child(.{
            .height = 1,
        });
        _ = controls_win.print(
            if (win.width >= 112) &.{
                .{ .text = "Controls:", .style = .{ .bold = true, .ul_style = .single } },
                .{ .text = " Exit: ctrl + c " },
            } else if (win.width >= 25) &.{
                .{ .text = "Controls:", .style = .{ .bold = true, .ul_style = .single } },
                .{ .text = " Win too small!" },
            } else &.{
                .{ .text = "" },
            },
            .{ .wrap = .none },
        );

        // Render the screen
        try vx.render(writer);
        try buffered_writer.flush();
    }
}
