# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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
