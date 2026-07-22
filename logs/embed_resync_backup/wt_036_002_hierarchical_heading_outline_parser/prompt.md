# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

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

## Module under test

```elixir
defmodule MarkdownOutline do
  @moduledoc """
  Parses a subset of Markdown into a nested outline tree driven by heading depth.

  Headings `#`..`######` create nodes; a heading deeper than the currently open
  node becomes its child, while a heading at the same or shallower level closes
  the branch and starts a sibling. Bullet items of the form
  `- **Name**: description (tag1, tag2)` attach to the deepest open node.
  """

  # One to (potentially) many "#" followed by whitespace and title text.
  @heading_re ~r/^(#+)\s+(.+?)\s*$/

  # Top-level bullet item: exactly one leading "-", a bold name, colon, description,
  # and an optional trailing "(tags)" group.
  @item_re ~r/^-\s+\*\*(.+?)\*\*:\s+(.*?)(?:\s+\(([^)]*)\))?\s*$/

  @doc """
  Parses `markdown` into a list of top-level outline node maps in document order.

  Each node is a map with `:title`, `:level`, `:items`, and `:children`. Bullet
  items attach to the deepest open node, and headings nest by relative depth.
  Returns `[]` for an empty document.
  """
  @spec parse(binary()) :: [map()]
  def parse(markdown) when is_binary(markdown) do
    {roots, stack} =
      markdown
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.map(&classify/1)
      |> Enum.reduce({[], []}, &step/2)

    finalize_stack(stack, roots)
  end

  # ---------------------------------------------------------------------------
  # Classification
  # ---------------------------------------------------------------------------

  defp classify(line) do
    cond do
      caps = Regex.run(@heading_re, line, capture: :all_but_first) ->
        [hashes, title] = caps
        level = String.length(hashes)
        if level <= 6, do: {:heading, level, String.trim(title)}, else: :ignore

      caps = Regex.run(@item_re, line, capture: :all_but_first) ->
        {:item, build_item(caps)}

      true ->
        :ignore
    end
  end

  defp build_item([name, description]), do: make(name, description, nil)
  defp build_item([name, description, raw]), do: make(name, description, raw)

  defp make(name, description, raw) do
    %{name: String.trim(name), description: String.trim(description), tags: tags(raw)}
  end

  defp tags(nil), do: []
  defp tags(""), do: []

  defp tags(raw) do
    raw
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # ---------------------------------------------------------------------------
  # Tree construction via an explicit stack of open nodes
  # ---------------------------------------------------------------------------
  #
  # {roots, stack}
  #   roots – completed top-level nodes, reversed
  #   stack – path from root to the deepest currently open node (head = deepest)
  #

  defp step({:item, item}, {roots, [top | rest]}) do
    {roots, [%{top | items: [item | top.items]} | rest]}
  end

  defp step({:item, _item}, {roots, []}), do: {roots, []}

  defp step({:heading, level, title}, {roots, stack}) do
    {roots, stack} = close_until(level, roots, stack)
    node = %{title: title, level: level, items: [], children: []}
    {roots, [node | stack]}
  end

  defp step(:ignore, acc), do: acc

  # Close (and attach) every open node whose level is >= the incoming level.
  defp close_until(level, roots, [%{level: tl} = top | rest]) when tl >= level do
    {roots, rest} = attach(top, roots, rest)
    close_until(level, roots, rest)
  end

  defp close_until(_level, roots, stack), do: {roots, stack}

  # Finalise `node` and attach it as a child of the next open node, or as a root.
  defp attach(node, roots, [parent | rest]) do
    {roots, [%{parent | children: [finalize(node) | parent.children]} | rest]}
  end

  defp attach(node, roots, []) do
    {[finalize(node) | roots], []}
  end

  # Flush any remaining open nodes at end-of-document.
  defp finalize_stack([], roots), do: Enum.reverse(roots)

  defp finalize_stack([top | rest], roots) do
    {roots, rest} = attach(top, roots, rest)
    finalize_stack(rest, roots)
  end

  defp finalize(%{items: items, children: children} = node) do
    %{node | items: Enum.reverse(items), children: Enum.reverse(children)}
  end
end
```
