# Bring this working module up to house style

I asked for the following:

Write me an Elixir module called `TreeValidator` that converts a flat list of node maps
into a nested tree, but with **collect-all diagnostics and best-effort repair** semantics
instead of fail-fast. Rather than stopping at the first problem, it gathers *every*
structural issue in the input, builds the best tree it can from the healthy remainder, and
reports what it had to work around.

Each node is a map that is guaranteed to have an `:id` field (a unique identifier: integer,
string, or atom). The `:parent_id` field may or may not be present; when absent, treat the
node as a root (and report it — see below). A present `:parent_id` is the parent's id, or
`nil` for a root.

I need this single public function:

- `TreeValidator.build(items)` — returns one of:
  - `{:ok, forest}` when the input has **no** structural issues. `forest` is a list of
    root-level nodes, each being the original map plus a `:children` key (recursively the
    same shape); leaves have `children: []`. Empty input returns `{:ok, []}`.
  - `{:issues, forest, issues}` when one or more issues were found. `forest` is the
    **best-effort** tree (possibly empty), and `issues` is a non-empty list describing
    every problem.

Each issue is a map `%{type: atom(), ids: [term()]}`. Detect these four types:

- `:duplicate_id` — one entry, `ids` = the ids that appeared more than once (in first-seen
  order). Repair: keep the **first** occurrence of each id; drop later duplicates.
- `:missing_parent_id` — one entry, `ids` = ids of nodes that lack the `:parent_id` key
  (in input order). Repair: treat each as a root.
- `:orphan` — one entry, `ids` = ids of nodes whose `parent_id` points to an id not present
  in the (deduplicated, non-cyclic) node set. Repair: raise each orphan to a root.
- `:cycle` — one entry **per distinct cycle**, `ids` = the ids forming that cycle. Repair:
  remove all nodes on the cycle from the forest (a non-cyclic node that referenced a removed
  cycle node then becomes an orphan, handled by the `:orphan` rule).

Ordering of the `issues` list: put the `:duplicate_id` entry (if any) first, then
`:missing_parent_id`, then `:orphan`, then one `:cycle` entry per cycle. Within the
best-effort forest, root order and sibling order follow the original input order (after
deduplication).

The result must always contain a usable `forest`, even when several different issues occur
together in one input. Cycle handling must catch both direct (A → B → A) and indirect
(A → B → C → A) cycles, and must not misreport valid deep trees.

Do not use any external dependencies — only the Elixir / Erlang standard library.
Give me the complete module in a single file.

Here is my implementation. It compiles and passes every test — the behavior
is correct — but it was rejected by the style review:

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

  @doc """
  Builds a best-effort forest and reports all structural issues.
  """
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
    colors = Map.put(colors, id, :grey)
    stack = [id | stack]
    child_ids = Map.get(children_map, id, [])

    result =
      Enum.reduce_while(child_ids, {:ok, colors}, fn child_id, {:ok, acc_colors} ->
        case Map.get(acc_colors, child_id) do
          :grey ->
            cycle = extract_cycle(child_id, [child_id | stack])
            {:halt, {:error, {:cycle_detected, cycle}}}

          :white ->
            case dfs(child_id, children_map, acc_colors, stack) do
              {:ok, new_colors} -> {:cont, {:ok, new_colors}}
              {:error, _} = err -> {:halt, err}
            end

          :black ->
            {:cont, {:ok, acc_colors}}

          nil ->
            {:cont, {:ok, acc_colors}}
        end
      end)

    case result do
      {:ok, colors} -> {:ok, Map.put(colors, id, :black)}
      {:error, _} = err -> err
    end
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

The style review said:

```
The solution is green but does not meet the house style: no @spec on any public function. Fix solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical and do not weaken test_harness.exs.
```

Fix every finding in the review WITHOUT changing any behavior: the module
must keep passing exactly the tests it passes now. Give me the complete
corrected module in a single file.
<!-- minted from logs/attempts/038_004_diagnostic_tree_validator_with_best_effort_repair_01/attempt_0 -->
