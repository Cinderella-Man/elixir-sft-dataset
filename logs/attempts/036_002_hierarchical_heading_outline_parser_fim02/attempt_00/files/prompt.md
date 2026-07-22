Implement the private `classify/1` function for the `MarkdownOutline` module.

`classify/1` takes a single already-trimmed line (a binary) and categorises it into
one of three tagged results that the tree-building `step/2` reducer understands:

- If the line matches the heading pattern `@heading_re` (captured with
  `capture: :all_but_first`, yielding `[hashes, title]`), compute the heading
  `level` as the number of `#` characters (`String.length(hashes)`). If `level <= 6`,
  return `{:heading, level, title}` with the title trimmed of surrounding whitespace
  via `String.trim/1`. If the level is 7 or more, return `:ignore`.
- Otherwise, if the line matches the bullet-item pattern `@item_re` (again captured
  with `capture: :all_but_first`), return `{:item, build_item(caps)}`, delegating the
  construction of the item map to the existing `build_item/1` helper.
- Otherwise (blank lines, unrecognised bullets, indented list items, over-long
  headings, etc.), return `:ignore`.

Use a `cond` expression that binds each `Regex.run/3` result and tests it for
truthiness, so the heading case is tried first, then the item case, then a `true`
fallthrough to `:ignore`.

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
    # TODO
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