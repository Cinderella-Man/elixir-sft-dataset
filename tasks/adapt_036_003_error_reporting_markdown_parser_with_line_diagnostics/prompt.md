# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule MarkdownParser do
  @moduledoc """
  Parses a subset of Markdown into structured category/item data.

  ## Document conventions

  * `## Heading` lines define category names (H2 only).
  * Bullet items beneath a heading follow the format:
    `- **Item Name**: description (tag1, tag2)`
  * Tags are optional; an item with no parentheses receives `tags: []`.
  * All other lines (blank lines, non-matching bullets, H1/H3+ headings,
    nested list items starting with more than one `-`) are silently ignored.
  * Bullet items that appear before the first `## heading` are discarded.
  """

  # ---------------------------------------------------------------------------
  # Compiled regexes (module-level constants)
  # ---------------------------------------------------------------------------

  # Matches exactly an H2 heading: "## Some Title"
  # Captures the trimmed heading text.
  @heading_re ~r/^##\s+(.+)$/

  # Matches a top-level bullet item that starts with exactly one "-" (not "  -",
  # not "--", etc.) and contains a bold name followed by a colon.
  # Group 1 – item name (inside **…**)
  # Group 2 – description (everything after ": " up to an optional trailing tag list)
  # Group 3 – raw tag string inside the final "(…)" if present
  @item_re ~r/^-\s+\*\*(.+?)\*\*:\s+(.*?)(?:\s+\(([^)]*)\))?\s*$/

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Parses `markdown` and returns a list of category maps in document order.

  ## Return shape

      [
        %{
          category: "Category Name",
          items: [
            %{name: "Item Name", description: "some description", tags: ["tag1", "tag2"]}
          ]
        }
      ]

  Returns `[]` for an empty string or a document with no H2 headings.
  """
  @spec parse(binary()) :: [%{category: String.t(), items: list(map())}]
  def parse(markdown) when is_binary(markdown) do
    markdown
    |> split_lines()
    |> classify_lines()
    |> build_categories()
  end

  # ---------------------------------------------------------------------------
  # Step 1 – split into trimmed lines, drop truly empty ones early
  # ---------------------------------------------------------------------------

  defp split_lines(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
  end

  # ---------------------------------------------------------------------------
  # Step 2 – classify each line as {:heading, name} | {:item, map} | :ignore
  # ---------------------------------------------------------------------------

  defp classify_lines(lines) do
    Enum.map(lines, &classify_line/1)
  end

  defp classify_line(line) do
    cond do
      match_heading(line) -> match_heading(line)
      match_item(line) -> match_item(line)
      true -> :ignore
    end
  end

  defp match_heading(line) do
    case Regex.run(@heading_re, line, capture: :all_but_first) do
      [name] -> {:heading, String.trim(name)}
      _ -> nil
    end
  end

  defp match_item(line) do
    case Regex.run(@item_re, line, capture: :all_but_first) do
      [name, description] ->
        {:item, build_item(name, description, nil)}

      [name, description, raw_tags] ->
        {:item, build_item(name, description, raw_tags)}

      _ ->
        nil
    end
  end

  defp build_item(name, description, raw_tags) do
    tags =
      case raw_tags do
        nil ->
          []

        "" ->
          []

        str ->
          str
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
      end

    %{name: String.trim(name), description: String.trim(description), tags: tags}
  end

  # ---------------------------------------------------------------------------
  # Step 3 – fold classified lines into a list of category maps
  # ---------------------------------------------------------------------------
  #
  # State:
  #   categories  – accumulated result list (reversed; reversed again at the end)
  #   current     – the category map being built, or nil if no heading seen yet
  #

  defp build_categories(classified_lines) do
    initial = %{categories: [], current: nil}

    %{categories: cats, current: last} =
      Enum.reduce(classified_lines, initial, &process_line/2)

    # Flush the final in-progress category (if any).
    cats =
      if last do
        [finalise(last) | cats]
      else
        cats
      end

    Enum.reverse(cats)
  end

  # A new H2 heading: flush current category (if any), open a new one.
  defp process_line({:heading, name}, %{categories: cats, current: current}) do
    cats =
      if current do
        [finalise(current) | cats]
      else
        cats
      end

    %{categories: cats, current: %{category: name, items: []}}
  end

  # A valid bullet item: append to the current category (discard if no heading yet).
  defp process_line({:item, item}, %{categories: cats, current: current}) do
    if current do
      %{categories: cats, current: Map.update!(current, :items, &[item | &1])}
    else
      %{categories: cats, current: nil}
    end
  end

  # Anything else: skip.
  defp process_line(:ignore, state), do: state

  # Reverse the items list (they were prepended for efficiency).
  defp finalise(%{category: name, items: items}) do
    %{category: name, items: Enum.reverse(items)}
  end
end
```

## New specification

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
- Input may use `\n` or `\r\n` line endings; each line's trailing whitespace (including a trailing carriage return) is stripped before it is classified, so CRLF documents parse identically to LF ones.
- Tags are trimmed individually and empty tags dropped; category titles are trimmed.
- The empty string returns `%{categories: [], errors: []}`.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.
