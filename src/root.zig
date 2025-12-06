//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const Io = std.Io;

const c = @cImport({
    @cInclude("cmark-gfm.h");
});

pub const RenderOptions = struct {
    /// Include a data-sourcepos attribute on all block elements.
    sourcepos: bool = false,

    /// Render softbreak elements as hard line breaks.
    hardbreaks: bool = false,

    // Render raw HTML and unsafe links (javascript:, vbscript:, file:, and data:, except for image/png, image/gif, image/jpeg, or image/webp mime types). By default, raw HTML is replaced /by a placeholder HTML comment. Unsafe links are replaced by empty strings.
    unsafe: bool = false,

    /// Render softbreak elements as spaces.
    nobreaks: bool = false,

    fn toCInt(opts: RenderOptions) c_int {
        return @as(c_int, @intCast(@intFromBool(opts.sourcepos))) << 1 |
            @as(c_int, @intCast(@intFromBool(opts.hardbreaks))) << 2 |
            @as(c_int, @intCast(@intFromBool(opts.unsafe))) << 17 |
            @as(c_int, @intCast(@intFromBool(opts.nobreaks))) << 4;
    }
};

pub const Width = union(enum) {
    unlimited: void,
    limited: c_int,

    pub fn toCInt(width: Width) c_int {
        return switch (width) {
            .unlimited => 0,
            .limited => |l| l,
        };
    }
};

pub const Node = struct {
    cmark: *c.cmark_node,

    pub const Type = enum(c_uint) {
        document = c.CMARK_NODE_TYPE_BLOCK | 0x0001,
        block_quote = c.CMARK_NODE_TYPE_BLOCK | 0x0002,
        list = c.CMARK_NODE_TYPE_BLOCK | 0x0003,
        item = c.CMARK_NODE_TYPE_BLOCK | 0x0004,
        code_block = c.CMARK_NODE_TYPE_BLOCK | 0x0005,
        html_block = c.CMARK_NODE_TYPE_BLOCK | 0x0006,
        custom_block = c.CMARK_NODE_TYPE_BLOCK | 0x0007,
        paragraph = c.CMARK_NODE_TYPE_BLOCK | 0x0008,
        heading = c.CMARK_NODE_TYPE_BLOCK | 0x0009,
        thematic_break = c.CMARK_NODE_TYPE_BLOCK | 0x000a,
        footnote_definition = c.CMARK_NODE_TYPE_BLOCK | 0x000b,

        text = c.CMARK_NODE_TYPE_INLINE | 0x0001,
        softbreak = c.CMARK_NODE_TYPE_INLINE | 0x0002,
        linebreak = c.CMARK_NODE_TYPE_INLINE | 0x0003,
        code = c.CMARK_NODE_TYPE_INLINE | 0x0004,
        html_inline = c.CMARK_NODE_TYPE_INLINE | 0x0005,
        custom_inline = c.CMARK_NODE_TYPE_INLINE | 0x0006,
        emph = c.CMARK_NODE_TYPE_INLINE | 0x0007,
        strong = c.CMARK_NODE_TYPE_INLINE | 0x0008,
        link = c.CMARK_NODE_TYPE_INLINE | 0x0009,
        image = c.CMARK_NODE_TYPE_INLINE | 0x000a,
        footnote_reference = c.CMARK_NODE_TYPE_INLINE | 0x000b,

        pub fn isBlock(@"type": Type) bool {
            return switch (@"type") {
                .document,
                .block_quote,
                .list,
                .item,
                .code_block,
                .html_block,
                .custom_block,
                .paragraph,
                .heading,
                .thematic_break,
                .footnote_definition,
                => true,
                else => false,
            };
        }
        pub fn isInline(@"type": Type) bool {
            return switch (@"type") {
                .text,
                .softbreak,
                .linebreak,
                .code,
                .html_inline,
                .custom_inline,
                .emph,
                .strong,
                .link,
                .image,
                .footnote_reference,
                => true,
                else => false,
            };
        }
    };

    pub fn firstChild(node: Node) ?Node {
        return .{
            .cmark = c.cmark_node_first_child(node.cmark) orelse return null,
        };
    }

    pub fn free(node: Node) void {
        defer c.cmark_node_free(node.cmark);
    }

    pub fn literal(node: Node) ?[]const u8 {
        const literal_ptr = c.cmark_node_get_literal(node.cmark) orelse return null;
        return std.mem.span(literal_ptr);
    }

    pub fn getType(node: Node) ?Type {
        const raw_type = c.cmark_node_get_type(node.cmark);
        if (raw_type == 0) return null;
        return @enumFromInt(raw_type);
    }

    pub fn url(node: Node) ?[]const u8 {
        const url_c = c.cmark_node_get_url(node.cmark) orelse return null;
        return std.mem.span(url_c);
    }

    pub fn next(node: Node) ?Node {
        const next_node = c.cmark_node_next(node.cmark) orelse return null;
        return .{ .cmark = next_node };
    }

    pub fn previous(node: Node) ?Node {
        const previous_node = c.cmark_node_next(node.cmark) orelse return null;
        return .{ .cmark = previous_node };
    }

    pub const CombinedOpts = struct {
        render: RenderOptions = .{},
        width: Width = .unlimited,
    };
    pub fn renderCommonmark(
        node: Node,
        allocator: Allocator,
        opts: CombinedOpts,
    ) ?[]const u8 {
        const commonmark = c.cmark_render_commonmark_with_mem(
            node.cmark,
            opts.render.toCInt(),
            opts.width.toCInt(),
            convertAllocator(allocator),
        ) orelse return null;
        return std.mem.span(commonmark);
    }

    pub fn renderHTML(
        node: Node,
        allocator: Allocator,
        options: CombinedOpts,
    ) ?[]const u8 {
        const html = c.cmark_render_html_with_mem(
            node.cmark,
            options.render.toCInt(),
            options.width.toCInt(),
            convertAllocator(allocator),
        ) orelse return null;
        return std.mem.span(html);
    }
};

pub const Parser = struct {
    cmark_parser: *c.cmark_parser,

    pub const Options = struct {
        /// Legacy option (no effect).
        normalize: bool = false,

        /// Validate UTF-8 in the input before parsing,
        /// replacing illegal sequences with the replacement character U+FFFD.
        validate_utf8: bool = false,

        /// Convert straight quotes to curly, --- to em dashes, -- to en dashes.
        smart: bool = false,

        /// Use GitHub-style tags for code blocks instead of .
        github_pre_lang: bool = false,

        /// Be liberal in interpreting inline HTML tags.
        liberal_html_tag: bool = false,

        /// Parse footnotes.
        footnotes: bool = false,

        /// Only parse strikethroughs if surrounded by exactly 2 tildes.
        /// Gives some compatibility with redcarpet.
        strikethrough_double_tilde: bool = false,

        /// Use style attributes to align table cells instead of align attributes.
        table_prefer_style_attributes: bool = false,

        /// Include the remainder of the info string in code blocks in a separate attribute.
        full_info_string: bool = false,

        pub fn toCInt(options: Options) c_int {
            return @as(c_int, @intCast(@intFromBool(options.validate_utf8))) << 9 |
                @as(c_int, @intCast(@intFromBool(options.smart))) << 10 |
                @as(c_int, @intCast(@intFromBool(options.github_pre_lang))) << 11 |
                @as(c_int, @intCast(@intFromBool(options.liberal_html_tag))) << 12 |
                @as(c_int, @intCast(@intFromBool(options.footnotes))) << 13 |
                @as(c_int, @intCast(@intFromBool(options.strikethrough_double_tilde))) << 14 |
                @as(c_int, @intCast(@intFromBool(options.table_prefer_style_attributes))) << 15 |
                @as(c_int, @intCast(@intFromBool(options.full_info_string))) << 16;
        }
    };
    pub fn init(allocator: Allocator, options: Options) Parser {
        return .{
            .cmark_parser = c.cmark_parser_new_with_mem(
                options.toCInt(),
                convertAllocator(allocator),
            ).?,
        };
    }
    pub fn deinit(parser: Parser) void {
        defer c.cmark_parser_free(parser.cmark_parser);
    }

    pub fn parse(parser: Parser, reader: *Io.Reader) !Node {
        while (true) {
            const buffered = reader.peekGreedy(1) catch |e| switch (e) {
                error.EndOfStream => break,
                else => |err| return err,
            };
            reader.tossBuffered();
            c.cmark_parser_feed(
                parser.cmark_parser,
                buffered.ptr,
                buffered.len,
            );
        }
        const root = c.cmark_parser_finish(parser.cmark_parser) orelse return error.ParseError;
        return .{ .cmark = root };
    }
};

pub const Iterator = struct {
    cmark: *c.cmark_iter,

    pub const Event = enum {
        none,
        done,
        enter,
        exit,

        fn fromC(ev: c.cmark_event_type) Event {
            return switch (ev) {
                c.CMARK_EVENT_NONE => .none,
                c.CMARK_EVENT_DONE => .done,
                c.CMARK_EVENT_ENTER => .enter,
                c.CMARK_EVENT_EXIT => .exit,
            };
        }
    };

    /// Creates a new iterator starting at root. The current node and event
    /// type are undefined until cmark_iter_next is called for the first time.
    /// The memory allocated for the iterator should be released using
    /// deinit when it is no longer needed.
    pub fn init(root_node: Node) Iterator {
        return .{ .cmark = c.cmark_iter_new(root_node.cmark).? };
    }

    pub fn deinit(iter: Iterator) void {
        defer c.cmark_iter_free(iter.cmark);
    }

    pub fn next(iter: Iterator) ?enum { enter, exit } {
        const ev_c = c.cmark_iter_next(iter.cmark);
        return switch (ev_c) {
            c.CMARK_EVENT_EXIT => .exit,
            c.CMARK_EVENT_ENTER => .enter,
            c.CMARK_EVENT_DONE => null,
            else => unreachable,
        };
    }

    pub fn node(iter: Iterator) Node {
        const node_c = c.cmark_iter_get_node(iter.cmark).?;
        return .{ .cmark = node_c };
    }
};

fn convertAllocator(child_allocator: Allocator) *c.struct_cmark_mem {
    // TODO Conversion api
    _ = child_allocator;
    const arena = c.cmark_get_arena_mem_allocator();
    return arena;
}

test "correct version" {
    const cmark_version_string = std.mem.span(c.cmark_version_string());
    try testing.expectEqualStrings("0.29.0.gfm.13", cmark_version_string);
}

test "parse from reader" {
    var input: Io.Reader = .fixed(
        \\# Hello World!
        \\
        \\First test **I** _write_:
        \\
        \\- A list of three things
        \\- poop
        \\- noob
    );
    const parser: Parser = .init(testing.allocator, .{});
    const root_node = try parser.parse(&input);

    const rendered = root_node.renderHTML(testing.allocator, .{}).?;
    try testing.expectEqualStrings(
        \\<h1>Hello World!</h1>
        \\<p>First test <strong>I</strong> <em>write</em>:</p>
        \\<ul>
        \\<li>A list of three things</li>
        \\<li>poop</li>
        \\<li>noob</li>
        \\</ul>
        \\
    , rendered);

    var types: std.ArrayList(Node.Type) = .empty;
    defer types.deinit(testing.allocator);
    const iter: Iterator = .init(root_node);
    defer iter.deinit();
    while (iter.next()) |ev| {
        if (ev == .exit) continue;
        const node = iter.node();
        try types.append(testing.allocator, node.getType().?);
    }
    const expected = &.{
        .document,
        .heading,
        .text,
        .paragraph,
        .text,
        .strong,
        .text,
        .text,
        .emph,
        .text,
        .text,
        .list,
        .item,
        .paragraph,
        .text,
        .item,
        .paragraph,
        .text,
        .item,
        .paragraph,
        .text,
    };
    try testing.expectEqualSlices(Node.Type, expected, types.items);
}

test "softbreak" {
    var input: Io.Reader = .fixed(
        \\What would this line break be considered?
        \\A soft line break :-)
    );
    const parser: Parser = .init(testing.allocator, .{});
    const root = try parser.parse(&input);

    var types: std.ArrayList(Node.Type) = .empty;
    defer types.deinit(testing.allocator);
    const iter: Iterator = .init(root);
    defer iter.deinit();
    while (iter.next()) |ev| {
        if (ev == .exit) continue;
        const node = iter.node();
        try types.append(testing.allocator, node.getType().?);
    }
    const expected = &.{ .document, .paragraph, .text, .softbreak, .text };
    try testing.expectEqualSlices(Node.Type, expected, types.items);
}
