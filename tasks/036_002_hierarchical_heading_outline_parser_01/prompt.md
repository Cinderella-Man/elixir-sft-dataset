Write me an Elixir module called `MarkdownOutline` that parses a Markdown document into a **nested outline tree** driven by heading depth.

Unlike a flat category list, this parser must respect the relative nesting of ATX headings (`#` … `######`). A heading whose level is deeper than the currently open heading becomes a **child** of it; a heading at the same or shallower level closes the previous branch and starts a new sibling (or ancestor's sibling).

The document format follows these conventions:
- Heading lines `# Title` … `###### Title` (one to six `#` characters followed by whitespace and text) define outline nodes. The number of `#` characters is the node's `level`.
- Bullet items beneath a heading follow the format: `- **Item Name**: description (tag1, tag2)` and attach to the **deepest currently open** heading node.
- Tags are optional — an item may end without parentheses (then `tags: []`).
- Any other lines (blank lines, non-matching bullets, nested list items indented with spaces, headings with more than six `#`) are silently ignored.
- Bullet items that appear before the first heading are discarded.

The single public function should be:
- `MarkdownOutline.parse(markdown_string)` which accepts a binary and returns a list of top-level node maps in document order:
  ```elixir
  [
    %{
      title: "Parent",
      level: 1,
      items: [%{name: "p", description: "pd", tags: ["a", "b"]}],
      children: [
        %{title: "Child", level: 2, items: [...], children: [...]}
      ]
    }
  ]
  ```

Specific behaviours to implement:
- Nesting is by **relative** level, not absolute: a `#` heading followed directly by a `###` heading makes the `###` a child of the `#` (the missing `##` level is not required).
- A heading with no items and no sub-headings still appears with `items: []` and `children: []`.
- Items and children of every node must be in document order.
- Tags are trimmed of surrounding whitespace individually and empty tags dropped.
- Category/node titles are trimmed of surrounding whitespace.
- Headings with seven or more `#` characters are ignored (treated as unrecognised lines).
- A `#` line with no whitespace between the hashes and the text (e.g. `#NotAHeading`) is not a heading and is ignored.
- Both `\n` (LF) and `\r\n` (CRLF) line endings must be supported: a trailing carriage return is stripped and never becomes part of a title, description, or tag.
- The function must handle an empty string input, returning `[]`.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.
