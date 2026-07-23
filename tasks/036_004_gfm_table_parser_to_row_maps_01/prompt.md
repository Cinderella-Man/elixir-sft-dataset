Hey — I need you to write me an Elixir module called `MarkdownTables` that pulls every GitHub-Flavored-Markdown **table** out of a document and hands each one back as structured row maps.

The way I think about a table: it's a contiguous block made of three parts. First, a header row of pipe-delimited cells, e.g. `| Name | Age |`. Second, a separator row immediately beneath it, where every cell matches the delimiter pattern `:?-+:?` (so things like `---`, `:---`, `---:`, `:---:`). Third, zero or more data rows — each a pipe-delimited line — running until the first line that isn't a pipe row.

I only want one public function out of this: `MarkdownTables.parse(markdown_string)`, which takes a binary and returns a list of table maps in document order. Concretely, I'm expecting shapes like this back:

```elixir
[
  %{
    headers: ["Name", "Age"],
    alignments: [:left, :right],
    rows: [%{"Name" => "Alice", "Age" => "30"}]
  }
]
```

Here are the parsing rules I need you to implement, and I care about all of them:

For line endings, split the document on `\n`, and strip any trailing carriage return (`\r`) off each line so that `\r\n` (CRLF) input parses identically to `\n` input and no `\r` leaks into the cell text.

For pipe rows, the leading and trailing `|` are optional; the cells are the text between unescaped `|` characters, each trimmed of the whitespace around it.

On escaped pipes: a `\|` inside a cell is a literal `|` and must NOT split the cell.

For separator validation: the row directly under the header only forms a table if it has the same number of cells as the header AND every cell matches `:?-+:?`. If that doesn't hold, then that "header" line isn't a table start — keep scanning from the next line, because a later line can still turn out to be the header.

Alignments get derived per separator cell: `:---` → `:left`, `---:` → `:right`, `:---:` → `:center`, `---` → `:none`. The `alignments` list has exactly one entry per header column.

For rows, key each data row by the header strings. If a row is ragged with **fewer** cells than there are headers, pad the missing columns with `""`; if it has **more** cells than headers, drop the extras.

Anything that isn't part of a table — prose, blank lines — just ignore it. The empty string returns `[]`, and a document with no valid table also returns `[]`.

Give me the complete module in a single file, and stick to the Elixir standard library only — no external dependencies.
