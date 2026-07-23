Hey, could you write me an Elixir module called `MarkdownParser` that parses a Markdown document and extracts structured data out of it? Here's the format I'm dealing with. Lines like `## Heading` define category names. Underneath each heading I've got bullet items that follow the format `- **Item Name**: description (tag1, tag2)`. The tags are optional, so an item might just end without any parentheses. Anything else — blank lines, bullets that don't match, nested list items that start with more than one `-` — I want silently ignored.

I only need one public function: `MarkdownParser.parse(markdown_string)`. It takes a binary and gives me back a list of category maps in document order, like this:

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

A few specific behaviours I care about. A `##` heading that has no valid bullet items beneath it (before the next heading comes along) should still show up in the output, just with `items: []`. Items with no tag parentheses should come through with `tags: []`. Trim each tag of whitespace individually, and trim the category names of any surrounding whitespace too. Only `##` (H2) headings define categories — `#`, `###`, and anything deeper should be ignored entirely, treated as unrecognised lines; and because they're just unrecognised lines, any valid bullet items following them still belong to the most recent `##` category. If there are bullet items sitting before any `##` heading shows up, discard them. The parser needs to tolerate both `\n` and `\r\n` (CRLF) line endings. And it has to handle an empty string input by returning `[]`.

Give me the complete module in a single file, please. Stick to the Elixir standard library only — no external dependencies.
