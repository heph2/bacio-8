const std = @import("std");
const zlua = @import("zlua");

fn is_directive(line: []const u8) bool {
    return line.len > 4 and
        line[0] == '_' and
        line[1] == '_' and
        line[line.len - 1] == '_' and
        line[line.len - 2] == '_';
}

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

fn dump_ppm(line: []const u8) !void {
    var buf: [196623]u8 = undefined;
    var pos: usize = 0;

    // header
    const h = try std.fmt.bufPrint(buf[pos..], "P3\n128 128\n255\n", .{});
    pos += h.len;

    for (line, 0..) |ch, i| {
        const rgb = hex_to_rgb(ch);

        // write RGB
        const s = try std.fmt.bufPrint(buf[pos..], "{s}", .{rgb});
        pos += s.len;

        // space between pixels
        if (i != line.len - 1) {
            buf[pos] = ' ';
            pos += 1;
        }
    }

    // newline at end of row
    buf[pos] = '\n';
    pos += 1;

    std.debug.print("{s}", .{buf[0..pos]});
}

// fn flushedStdoutPrint(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
//     var out_buf: [4096]u8 = undefined;
//     var w = std.Io.File.stdout().writer(io, &out_buf);
//     const stdout = &w.interface;
//     try stdout.print(fmt, args);
//     try stdout.flush();
// }

pub fn main() !void {
    var gba = std.heap.DebugAllocator(.{}){};
    defer _ = gba.deinit();
    const alloc = gba.allocator();

    const filename = "test_gfx.p8";
    // const delimiter = "\n";
    var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });

    defer file.close();

    var read_buf: [4096]u8 = undefined; // 4KB
    var in_lua = false;
    var in_gfx = false;

    var gfx_section: std.ArrayList(u8) = .empty;
    defer gfx_section.deinit(alloc);

    var lua_source: std.ArrayList(u8) = .empty;
    // defer lua_source(alloc);
    defer lua_source.deinit(alloc);

    std.debug.print("ciao\n", .{});
    while (true) {
        const n = try file.read(&read_buf);
        if (n == 0) break;

        var start: usize = 0;

        for (read_buf[0..n], 0..) |c, i| {
            if (c == '\n') {
                const line = read_buf[start..i];

                if (std.mem.eql(u8, line, "__lua__")) {
                    std.debug.print("Found lua section\n", .{});
                    in_lua = true;
                    start = i + 1;
                    continue;
                }

                if (std.mem.eql(u8, line, "__gfx__")) {
                    std.debug.print("Found gfx section\n", .{});
                    in_gfx = true;
                    in_lua = false;
                    start = i + 1;
                    continue;
                }

                if (in_lua and is_directive(line)) {
                    std.debug.print("Exiting lua section\n", .{});
                    in_lua = false;
                    break; // end of lua section
                }

                if (in_gfx and is_directive(line)) {
                    std.debug.print("Exiting gfx section\n", .{});
                    break; // end of gfx section
                }

                if (in_lua) {
                    std.debug.print("adding lua line\n", .{});
                    try lua_source.appendSlice(alloc, line);
                    try lua_source.append(alloc, '\n');
                }

                if (in_gfx) {
                    std.debug.print("Adding gfx line\n", .{});
                    try gfx_section.appendSlice(alloc, line);
                    try gfx_section.append(alloc, '\n');
                }

                start = i + 1;
            }
        }
    }

    std.debug.print("sono fuori dal tunnel\n", .{});

    // for (lua_source.items) |str| {
    //     std.debug.print("{s}\n", .{str});
    // }
    //
    std.debug.print("{s}\n", .{lua_source.items});
    // execute lua script
    var lua = try zlua.Lua.init(alloc);
    defer lua.deinit();

    lua.openLibs();

    try lua_source.append(alloc, 0);

    const zstr: [:0]const u8 = lua_source.items[0 .. lua_source.items.len - 1 :0];

    lua.loadString(zstr) catch {
        // try flushedStdoutPrint(io, "{s}\n", .{lua.toString(-1) catch unreachable});

        std.debug.print("Lua error during loading is: {s}\n", .{lua.toString(-1) catch unreachable});
        lua.pop(1);
    };
    // const script: [:0]const u8 = std.mem.span(lua_source.items);
    lua.protectedCall(.{}) catch {
        std.debug.print("Lua error is: {s}\n", .{lua.toString(-1) catch unreachable});
        lua.pop(1);
    };

    // for (gfx_section.items) |str| {
    //     std.debug.print("{s}\n", .{str});
    // }
    //

    std.debug.print("{s}\n", .{gfx_section.items});
    // try to create a ppm file for visualize the spritesheet

    try dump_ppm(gfx_section.items);

    // null terminate buffer
    // try lua_source.append(alloc, 0);

    // try lua_source.append(alloc, 0);
    // try lua.doString(std.mem.span(lua_source.items));
}
