const std = @import("std");
const zlua = @import("zlua");

fn is_directive(line: []const u8) bool {
    return line.len > 4 and
        line[0] == '_' and
        line[1] == '_' and
        line[line.len - 1] == '_' and
        line[line.len - 2] == '_';
}

pub fn main() !void {
    var gba = std.heap.DebugAllocator(.{}){};
    defer _ = gba.deinit();
    const alloc = gba.allocator();

    const filename = "test.p8";
    // const delimiter = "\n";
    var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });

    defer file.close();

    var read_buf: [4096]u8 = undefined; // 4KB
    var in_lua = false;

    var lua_source: std.ArrayList(u8) = .empty;
    // defer lua_source(alloc);

    while (true) {
        const n = try file.read(&read_buf);
        if (n == 0) break;

        var start: usize = 0;

        for (read_buf[0..n], 0..) |c, i| {
            if (c == '\n') {
                const line = read_buf[start..i];

                if (std.mem.eql(u8, line, "__lua__")) {
                    in_lua = true;
                    start = i + 1;
                    continue;
                }

                if (in_lua and is_directive(line)) {
                    return; // end of lua section
                }

                if (in_lua) {
                    try lua_source.appendSlice(alloc, line);
                    try lua_source.append(alloc, '\n');
                }

                start = i + 1;
            }
        }
    }

    // execute lua script
    var lua = try zlua.Lua.init(alloc);
    defer lua.deinit();

    try lua_source.append(alloc, 0);
    try lua.doString(std.mem.span(lua_source.items));
}
