Implement the private `attach/3` function.

`attach/3` takes an open outline `node`, the accumulator of completed top-level
`roots` (stored reversed), and the current `stack` of still-open ancestor nodes
(head = the next-shallower open node). Its job is to *finalise* `node` and place
it where it belongs, returning an updated `{roots, stack}` tuple.

It must:
- First finalise `node` with `finalize/1` (which reverses its accumulated `items`
  and `children` into document order).
- If the `stack` is non-empty, treat its head as the `parent`: prepend the
  finalised node onto that parent's `children` list (children are kept reversed
  during construction) and return the roots unchanged together with the stack
  whose head is the updated parent (i.e. `{roots, [%{parent | children: [...]} | rest]}`).
- If the `stack` is empty, the node is a top-level node: prepend the finalised
  node onto `roots` and return `{[finalized | roots], []}`.

Write it as two function clauses (one for the non-empty stack, one for the empty
stack).

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

  defp attach(node, roots, [parent | rest]) do
    # TODO
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