# Fill in the middle: `TreePaths.build/2`

Implement the public `build/2` function for the `TreePaths` module below. All of the
private helper functions it relies on (`index_items/1`, `detect_duplicate_ids/1`,
`build_children_map/1`, `detect_cycle/2`, and `flatten/5`) are already provided — your
job is only to write the `build/2` clauses that wire them together.

`build/2` converts a flat list of node maps into a flat, pre-order annotated list. It
takes `items` (a list of maps, each with at least `:id` and `:parent_id`) and an optional
keyword list `opts`, and should behave as follows:

- Provide a default argument so it can be called as `build(items)` or `build(items, opts)`.
- If `items` is the empty list, return `{:ok, []}` immediately.
- Otherwise (when `items` is a list):
  - Read the `:orphan_strategy` option from `opts`, defaulting to `:discard`.
  - Build an id-to-node map and the list of ids in original input order using
    `index_items/1`.
  - Check for duplicate ids with `detect_duplicate_ids/1`; if it returns an `{:error, _}`
    tuple, propagate that error unchanged.
  - Build the parent-to-children map with `build_children_map/1`, and compute the set of
    known ids (a `MapSet` of the ordered ids).
  - Run `detect_cycle/2` over the ordered ids and children map; if it returns an
    `{:error, _}` tuple, propagate that error unchanged.
  - Determine the root ids by filtering the ordered ids, preserving input order. A node is
    a root when its `parent_id` is `nil`. When its `parent_id` refers to an id that is not
    a known id, it counts as a root only if `orphan_strategy == :raise_to_root` (otherwise
    it — and its descendants — are dropped). A node whose `parent_id` points to an existing
    id is never a root.
  - For each root id, in order, produce its annotated subtree by calling
    `flatten(id, id_to_node, children_map, 0, [])`, and concatenate the results into a
    single flat pre-order list.
  - Return `{:ok, nodes}`.

```elixir
defmodule TreePaths do
  @moduledoc """
  Converts a flat list of node maps into a flat, pre-order annotated list
  (a "materialized path" representation).

  Each input map must have at least:
    - `:id`        — a unique identifier (any term)
    - `:parent_id` — the id of the parent node, or `nil` for root nodes

  `build/2` returns nodes in pre-order DFS order, each annotated with `:depth`
  and `:path` (root-to-node id list). `subtree/2` extracts a node and all of
  its descendants from that annotated list.
  """

  @type id :: term()

  @doc """
  Builds the annotated, pre-order list from a flat list of node maps.

  Options:
    - `:orphan_strategy` — `:discard` (default) drops nodes whose `parent_id`
      references a missing id; `:raise_to_root` promotes them to roots.
  """
  @spec build([map()], keyword()) :: {:ok, [map()]} | {:error, term()}
  # TODO: implement build/2

  @doc """
  Returns `{:ok, slice}` — the node with the given id and all of its
  descendants (every node whose `:path` contains `id`) in pre-order — or
  `{:error, :not_found}` when the id is not present.
  """
  @spec subtree([map()], id()) :: {:ok, [map()]} | {:error, :not_found}
  def subtree(nodes, id) when is_list(nodes) do
    if Enum.any?(nodes, &(&1.id == id)) do
      {:ok, Enum.filter(nodes, fn node -> id in node.path end)}
    else
      {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp flatten(id, id_to_node, children_map, depth, ancestor_path) do
    node = Map.fetch!(id_to_node, id)
    path = ancestor_path ++ [id]

    annotated =
      node
      |> Map.put(:depth, depth)
      |> Map.put(:path, path)

    child_ids = Map.get(children_map, id, [])

    descendants =
      Enum.flat_map(child_ids, fn child_id ->
        flatten(child_id, id_to_node, children_map, depth + 1, path)
      end)

    [annotated | descendants]
  end

  defp index_items(items) do
    {map, ids} =
      Enum.reduce(items, {%{}, []}, fn item, {map, ids} ->
        id = Map.fetch!(item, :id)
        {Map.put(map, id, item), [id | ids]}
      end)

    {map, Enum.reverse(ids)}
  end

  defp detect_duplicate_ids(items) do
    ids = Enum.map(items, & &1.id)
    unique = Enum.uniq(ids)

    if length(ids) == length(unique) do
      :ok
    else
      dupes =
        ids
        |> Enum.frequencies()
        |> Enum.filter(fn {_id, count} -> count > 1 end)
        |> Enum.map(fn {id, _} -> id end)

      {:error, {:duplicate_ids, dupes}}
    end
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