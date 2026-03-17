const std = @import("std");
const zlua = @import("zlua");

fn hex_to_rgb(index: u8) []const u8 {
    return switch (index) {
        '0' => "0 0 0",
        '1' => "29 43 83",
        '2' => "126 37 83",
        '3' => "0 135 81",
        '4' => "171 82 54",
        '5' => "95 87 79",
        '6' => "194 195 199",
        '7' => "255 241 232",
        '8' => "255 0 77",
        '9' => "255 163 0",
        'a' => "255 236 39",
        'b' => "0 228 54",
        'c' => "41 173 255",
        'd' => "131 118 156",
        'e' => "255 119 168",
        'f' => "255 204 170",
        else => "0 0 0",
    };
}

fn dump_ppm(lines: [][]const u8) !void {
    if (lines.len != 128) {
        std.debug.panic("expected 128 gfx rows, got {}", .{lines.len});
    }

    for (lines) |line| {
        if (line.len != 128) {
            std.debug.panic("invalid row length {}", .{line.len});
        }
    }

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&out_buf);
    const stdout = &stdout_writer.interface;

    try stdout.print("P3\n128 128\n255\n", .{});

    for (lines) |line| {
        for (line, 0..) |ch, i| {
            try stdout.print("{s}", .{hex_to_rgb(ch)});
            if (i != 127) try stdout.print(" ", .{});
        }
        try stdout.print("\n", .{});
    }
    stdout.flush() catch |err| {
        std.debug.print("Error flushing stdout buffer: {any}\n", .{err});
    };
}

pub fn main() !void {
    var gba = std.heap.DebugAllocator(.{}){};
    defer _ = gba.deinit();
    const alloc = gba.allocator();

    const filename = "test.p8";
    const delimiter = "\n";
    var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });

    defer file.close();

    var read_buf: [4096]u8 = undefined; // 4KB
    var in_lua = false;
    var in_gfx = false;
    var in_sfx = false;

    var gfx_section: std.ArrayList([]const u8) = .empty;
    var lua_section: std.ArrayList(u8) = .empty;
    var sfx_section: std.ArrayList([]const u8) = .empty;

    defer {
        for (gfx_section.items) |row| {
            alloc.free(row);
        }
        gfx_section.deinit(alloc);

        lua_section.deinit(alloc);

        for (sfx_section.items) |row| {
            alloc.free(row);
        }
        sfx_section.deinit(alloc);
    }

    // Reader section
    var f_reader: std.fs.File.Reader = file.reader(&read_buf);
    var line = std.Io.Writer.Allocating.init(alloc);
    defer line.deinit();

    while (true) {
        _ = f_reader.interface.streamDelimiter(&line.writer, delimiter[0]) catch |err| {
            if (err == error.EndOfStream) break else return err;
        };
        _ = f_reader.interface.toss(1); // skip the delimiter byte.

        if (line.written().len == 0) {
            line.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, line.written(), "__lua__")) {
            std.debug.print("Found lua section\n", .{});
            in_lua = true;
            line.clearRetainingCapacity();
            continue;
        }

        if (std.mem.eql(u8, line.written(), "__gfx__")) {
            std.debug.print("Found gfx section\n", .{});
            in_gfx = true;
            in_lua = false;
            line.clearRetainingCapacity();
            continue;
        }

        if (std.mem.eql(u8, line.written(), "__sfx__")) {
            std.debug.print("Found sfx section\n", .{});
            in_gfx = false;
            in_sfx = true;
            line.clearRetainingCapacity();
            continue;
        }

        if (in_lua) {
            try lua_section.appendSlice(alloc, line.written());
            try lua_section.append(alloc, '\n');
        }

        if (in_gfx) {
            const copy = try alloc.dupe(u8, line.written());
            try gfx_section.append(alloc, copy);
        }

        if (in_sfx) {
            const copy = try alloc.dupe(u8, line.written());
            try sfx_section.append(alloc, copy);
        }

        line.clearRetainingCapacity(); // reset the accumulating buffer.
    }

    // execute lua script
    var lua = try zlua.Lua.init(alloc);
    defer lua.deinit();
    lua.openLibs();

    try lua_section.append(alloc, 0);
    const zstr: [:0]const u8 = lua_section.items[0 .. lua_section.items.len - 1 :0];
    lua.loadString(zstr) catch {
        std.debug.print("Lua error during loading is: {s}\n", .{lua.toString(-1) catch unreachable});
        lua.pop(1);
    };
    lua.protectedCall(.{}) catch {
        std.debug.print("Lua error is: {s}\n", .{lua.toString(-1) catch unreachable});
        lua.pop(1);
    };

    // dump ppm from gfx section
    try dump_ppm(gfx_section.items);
}
