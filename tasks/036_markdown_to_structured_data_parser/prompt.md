Write me an Elixir module called `MarkdownParser` that parses a Markdown document and extracts structured data from it.

The document format follows these conventions:
- `## Heading` lines define category names
- Bullet items underneath each heading follow the format: `- **Item Name**: description (tag1, tag2)`
- Tags are optional — an item may end without parentheses
- Any other lines (blank lines, non-matching bullets, nested list items starting with more than one `-`) should be silently ignored

The single public function should be:
- `MarkdownParser.parse(markdown_string)` which accepts a binary and returns a list of category maps in document order:
  ```elixir
  [
    %{
      category: "Category Name",
      items: [
        %{name: "Item Name", description: "some description", tags: ["tag1", "tag2"]}
      ]
    }
  ]
  ```

Specific behaviours to implement:
- A `##` heading with no valid bullet items beneath it (before the next heading) should still appear in the output with `items: []`
- Items with no tag parentheses should have `tags: []`
- Tags should be trimmed of whitespace individually
- Only `##` (H2) headings define categories — `#`, `###`, and deeper headings should be ignored entirely (treated as unrecognised lines)
- If the document has bullet items before any `##` heading appears, discard them
- The function must handle an empty string input, returning `[]`

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.