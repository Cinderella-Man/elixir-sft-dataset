Implement the private `dfs/4` function. It performs one depth-first traversal
from a starting node, using white/grey/black colouring to detect a cycle in the
parent→child graph.

`dfs(id, children_map, colors, stack)` takes the current node `id`, the
`children_map` (a map from an id to the list of its child ids), the current
`colors` map (each id mapped to `:white`, `:grey`, or `:black`), and the current
DFS `stack` (the list of ancestor ids on the active path, most-recent first).

It must:

1. Mark `id` as `:grey` in `colors` and push `id` onto `stack`.
2. Look up `id`'s children (defaulting to `[]` when absent) and walk them in
   order, threading the evolving `colors` through each step:
   - If a child is `:grey`, a back-edge closes a cycle: build the cycle's id list
     with `extract_cycle(child_id, [child_id | stack])` and stop, returning
     `{:error, {:cycle_detected, cycle}}`.
   - If a child is `:white`, recurse into it with `dfs/4`; propagate an `{:ok,
     new_colors}` by continuing with the updated colours, or short-circuit on an
     `{:error, _}`.
   - If a child is `:black` (already fully explored) or `nil` (unknown id),
     leave the colours unchanged and continue.
3. If every child was processed without error, mark `id` as `:black` and return
   `{:ok, colors}`. If any child produced an error, return that error unchanged.

The returned `colors` map must carry forward all colour updates made during the
traversal so the caller can continue from where this call left off.

```elixir
defmodule TreeValidator do
  @moduledoc """
  Converts a flat list of node maps into a nested tree using collect-all
  diagnostics and best-effort repair, rather than fail-fast.

  Every node is assumed to have an `:id`. `:parent_id` may be absent (treated as
  a root and reported). `build/1` returns `{:ok, forest}` when the input is
  clean, or `{:issues, forest, issues}` with a best-effort forest and a list of
  every structural problem found (duplicate ids, missing parent keys, orphans,
  and cycles).
  """

  @typedoc "A node map from the input list; must contain an `:id` key."
  @type node_map :: map()

  @typedoc "A node map plus a recursive `:children` list."
  @type tree_node :: map()

  @typedoc "A single reported structural problem."
  @type issue :: %{type: atom(), ids: [term()]}

  @doc """
  Builds a best-effort forest and reports all structural issues.

  Returns `{:ok, forest}` when the input has no structural issues, or
  `{:issues, forest, issues}` with the best-effort `forest` and a non-empty
  list of `issues` otherwise.
  """
  @spec build([node_map()]) ::
          {:ok, [tree_node()]} | {:issues, [tree_node()], [issue()]}
  def build([]), do: {:ok, []}

  def build(items) when is_list(items) do
    {normalized, missing_pid_ids} = normalize(items)
    {deduped, dup_ids} = dedup(normalized)
    {cycles, acyclic} = extract_cycles(deduped)

    known = MapSet.new(Enum.map(acyclic, & &1.id))

    orphan_ids =
      for item <- acyclic,
          not is_nil(item.parent_id),
          not MapSet.member?(known, item.parent_id),
          do: item.id

    forest = build_forest(acyclic, known)
    issues = assemble(dup_ids, missing_pid_ids, orphan_ids, cycles)

    case issues do
      [] -> {:ok, forest}
      _ -> {:issues, forest, issues}
    end
  end

  # ---------------------------------------------------------------------------
  # Normalization / deduplication
  # ---------------------------------------------------------------------------

  defp normalize(items) do
    {normed, missing} =
      Enum.map_reduce(items, [], fn item, missing ->
        if Map.has_key?(item, :parent_id) do
          {item, missing}
        else
          {Map.put(item, :parent_id, nil), [item.id | missing]}
        end
      end)

    {normed, Enum.reverse(missing)}
  end

  defp dedup(items) do
    {kept, _seen, dups} =
      Enum.reduce(items, {[], MapSet.new(), []}, fn item, {kept, seen, dups} ->
        if MapSet.member?(seen, item.id) do
          {kept, seen, [item.id | dups]}
        else
          {[item | kept], MapSet.put(seen, item.id), dups}
        end
      end)

    {Enum.reverse(kept), dups |> Enum.reverse() |> Enum.uniq()}
  end

  # ---------------------------------------------------------------------------
  # Cycle extraction (repeatedly remove detected cycles)
  # ---------------------------------------------------------------------------

  defp extract_cycles(items), do: do_extract(items, [])

  defp do_extract(items, acc) do
    ordered_ids = Enum.map(items, & &1.id)
    children_map = build_children_map(items)

    case detect_cycle(ordered_ids, children_map) do
      :ok ->
        {Enum.reverse(acc), items}

      {:error, {:cycle_detected, cycle_ids}} ->
        cycle_set = MapSet.new(cycle_ids)
        remaining = Enum.reject(items, fn item -> MapSet.member?(cycle_set, item.id) end)
        do_extract(remaining, [cycle_ids | acc])
    end
  end

  # ---------------------------------------------------------------------------
  # Best-effort forest construction (orphans raised to root)
  # ---------------------------------------------------------------------------

  defp build_forest(items, known) do
    id_to_node = Map.new(items, fn item -> {item.id, item} end)
    ordered_ids = Enum.map(items, & &1.id)
    children_map = build_children_map(items)

    root_ids =
      Enum.filter(ordered_ids, fn id ->
        pid = Map.fetch!(id_to_node, id).parent_id
        is_nil(pid) or not MapSet.member?(known, pid)
      end)

    Enum.map(root_ids, &build_subtree(&1, id_to_node, children_map))
  end

  defp build_subtree(id, id_to_node, children_map) do
    node = Map.fetch!(id_to_node, id)
    child_ids = Map.get(children_map, id, [])

    children =
      Enum.map(child_ids, fn child_id ->
        build_subtree(child_id, id_to_node, children_map)
      end)

    Map.put(node, :children, children)
  end

  defp build_children_map(items) do
    Enum.reduce(items, %{}, fn item, acc ->
      pid = item.parent_id

      if is_nil(pid) do
        acc
      else
        Map.update(acc, pid, [item.id], fn existing -> existing ++ [item.id] end)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Issue assembly
  # ---------------------------------------------------------------------------

  defp assemble(dup_ids, missing_ids, orphan_ids, cycles) do
    []
    |> maybe_add(dup_ids, :duplicate_id)
    |> maybe_add(missing_ids, :missing_parent_id)
    |> maybe_add(orphan_ids, :orphan)
    |> Kernel.++(Enum.map(cycles, fn cycle -> %{type: :cycle, ids: cycle} end))
  end

  defp maybe_add(acc, [], _type), do: acc
  defp maybe_add(acc, ids, type), do: acc ++ [%{type: type, ids: ids}]

  # ---------------------------------------------------------------------------
  # Cycle detection — iterative DFS (white/grey/black colouring)
  # ---------------------------------------------------------------------------

  defp detect_cycle(all_ids, children_map) do
    initial_colors = Map.new(all_ids, fn id -> {id, :white} end)

    Enum.reduce_while(all_ids, {:ok, initial_colors}, fn id, {:ok, colors} ->
      if Map.get(colors, id) == :white do
        case dfs(id, children_map, colors, []) do
          {:ok, new_colors} -> {:cont, {:ok, new_colors}}
          {:error, _} = err -> {:halt, err}
        end
      else
        {:cont, {:ok, colors}}
      end
    end)
    |> case do
      {:ok, _colors} -> :ok
      {:error, _} = err -> err
    end
  end

  defp dfs(id, children_map, colors, stack) do
    # TODO
  end

  defp extract_cycle(cycle_root, path) do
    path
    |> Enum.reverse()
    |> Enum.drop_while(fn id -> id != cycle_root end)
    |> Enum.uniq()
    |> case do
      [] -> [cycle_root]
      slice -> slice
    end
  end
end
```