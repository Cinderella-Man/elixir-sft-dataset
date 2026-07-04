Implement the private `close_until/3` function. Its job is to prepare the open-node
stack for an incoming heading by closing every branch that the new heading should end.

It receives three arguments: the incoming heading's `level`, the accumulated list of
completed top-level nodes `roots` (reversed), and the `stack` of currently open nodes
(the path from the root down to the deepest open node, with the deepest node at the
head). It must pop and finalise every open node whose own `level` is greater than or
equal to the incoming `level` — those nodes are siblings or ancestors of the new
heading, so they can no longer receive children. For each such node it should use
`attach/3` to finalise the node and either add it as a child of the next open node or
promote it to a root, then continue closing recursively. Once the head of the stack is
a node whose level is strictly less than the incoming `level` (or the stack is empty),
it stops and returns the resulting `{roots, stack}` tuple, which leaves the correct
parent open to receive the new heading as a child.

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
  defp close_until(level, roots, stack) do
    # TODO
  end

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