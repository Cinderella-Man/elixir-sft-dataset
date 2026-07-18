Write me an Elixir module called `MarkdownTables` that extracts every GitHub-Flavored-Markdown **table** in a document and returns each as structured row maps.

A table is a contiguous block of three parts:
1. A header row of pipe-delimited cells, e.g. `| Name | Age |`.
2. A separator row immediately beneath it, where every cell matches the delimiter pattern `:?-+:?` (e.g. `---`, `:---`, `---:`, `:---:`).
3. Zero or more data rows (each a pipe-delimited line) until the first line that is not a pipe row.

The single public function should be:
- `MarkdownTables.parse(markdown_string)` which accepts a binary and returns a list of table maps in document order:
  ```elixir
  [
    %{
      headers: ["Name", "Age"],
      alignments: [:left, :right],
      rows: [%{"Name" => "Alice", "Age" => "30"}]
    }
  ]
  ```

Parsing rules to implement:
- **Line endings**: split the document on `\n`, and strip any trailing carriage return (`\r`) from each line so that `\r\n` (CRLF) input parses identically to `\n` input and no `\r` leaks into cell text.
- **Pipe rows**: leading and trailing `|` are optional; cells are the text between unescaped `|` characters, each trimmed of surrounding whitespace.
- **Escaped pipes**: a `\|` inside a cell is a literal `|` and does NOT split the cell.
- **Separator validation**: the row directly under the header only forms a table if it has the same number of cells as the header AND every cell matches `:?-+:?`. Otherwise the "header" line is not a table start and scanning continues from the next line (a later line can still become the header).
- **Alignments**, derived per separator cell: `:---` → `:left`, `---:` → `:right`, `:---:` → `:center`, `---` → `:none`. The `alignments` list has one entry per header column.
- **Rows**: each data row is keyed by the header strings. A ragged row with **fewer** cells than headers pads the missing columns with `""`; a row with **more** cells than headers drops the extras.
- Lines that are not part of any table (prose, blank lines) are ignored.
- The empty string returns `[]`; a document with no valid table returns `[]`.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.
