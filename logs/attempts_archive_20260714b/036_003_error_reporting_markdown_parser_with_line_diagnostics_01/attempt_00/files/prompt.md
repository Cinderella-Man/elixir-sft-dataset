Write me an Elixir module called `MarkdownReport` that parses a Markdown document into structured categories **and reports every line it could not interpret**, with line numbers.

This is a strict, diagnostic variant: rather than silently ignoring malformed content, it collects errors so a caller can surface them.

The document format follows the same conventions as a flat category parser:
- `## Heading` lines (exactly two `#`) define category names.
- Bullet items underneath a heading follow the format: `- **Item Name**: description (tag1, tag2)`.
- Tags are optional — an item may end without parentheses (then `tags: []`).
- Blank lines and arbitrary prose are silently ignored (they are not errors).

The single public function should be:
- `MarkdownReport.parse(markdown_string)` which accepts a binary and returns a map:
  ```elixir
  %{
    categories: [
      %{category: "Name", items: [%{name: "n", description: "d", tags: ["t"]}]}
    ],
    errors: [
      %{line: 3, content: "- oops", reason: :malformed_item}
    ]
  }
  ```

Diagnostic rules to implement (line numbers are 1-indexed against the original document, before any splitting on the next heading):
- **`:unsupported_heading`** — a heading with one `#` (H1) or three-plus `#` (H3+). It is reported and does **not** open a category, but it also does **not** close the currently open category (a following item still attaches to that category).
- **`:malformed_item`** — a line that starts at column zero with `- ` (a single dash and whitespace) but does not match the `- **Name**: description` format. (Space-indented / nested bullets are NOT reported — they are silently ignored.)
- **`:orphan_item`** — a well-formed bullet item that appears before any `##` heading has opened a category. It is reported and discarded.
- **`:duplicate_category`** — a `##` heading whose (trimmed) title equals one already seen. It is reported, the earlier category is flushed, and the duplicate section is **suppressed**: bullet items under it are silently ignored (not reported as orphans) until the next distinct heading.

Additional requirements:
- `categories` are in document order; items within a category are in document order.
- Every reported error carries the original (trailing-whitespace-trimmed) line content and its 1-indexed line number; `errors` are in ascending line order.
- Tags are trimmed individually and empty tags dropped; category titles are trimmed.
- The empty string returns `%{categories: [], errors: []}`.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.