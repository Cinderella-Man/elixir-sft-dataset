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
- The function must handle an empty string input, returning `[]`.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.
