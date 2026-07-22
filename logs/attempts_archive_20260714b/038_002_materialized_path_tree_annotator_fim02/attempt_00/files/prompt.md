# Task: Implement `dfs/4` in `TreePaths`

`TreePaths` converts a flat list of `%{id: ..., parent_id: ...}` maps into a
flat, pre-order annotated list. As part of `build/2`, the module runs an
iterative white/grey/black depth-first traversal to detect cycles before it
tries to flatten the tree. The public `detect_cycle/2` entry point colours every
id `:white`, then calls the private recursive worker `dfs/4` once per still-white
id.

Implement the private `dfs/4` function. Its signature is
`dfs(id, children_map, colors, stack)`, where `colors` maps every id to
`:white | :grey | :black` and `stack` is the list of ancestor ids on the current
DFS path (most recent first). It must:

1. Mark `id` as `:grey` in `colors` (it is now on the active path) and push `id`
   onto `stack`.
2. Look up the child ids for `id` in `children_map` (defaulting to `[]` when the
   id has no entry).
3. Walk the child ids left-to-right, threading the working `colors` map through
   the traversal (use `Enum.reduce_while/3` starting from `{:ok, colors}`). For
   each `child_id`, dispatch on its current colour:
   - `:grey` — the child is already on the active path, so this edge closes a
     cycle. Build the cycle with `extract_cycle(child_id, [child_id | stack])`
     and halt the whole traversal with
     `{:error, {:cycle_detected, cycle}}`.
   - `:white` — recurse with `dfs(child_id, children_map, acc_colors, stack)`
     (passing the current, id-pushed `stack`). On `{:ok, new_colors}` continue
     with the updated colours; on `{:error, _}` halt and propagate the error.
   - `:black` — already fully explored; continue unchanged.
   - `nil` — unknown id; continue unchanged.
4. After the children are processed: if the reduction ended in `{:ok, colors}`,
   mark `id` as `:black` (fully explored) and return `{:ok, colors}`. If it
   ended in `{:error, _}`, return that error unchanged.

So `dfs/4` returns either `{:ok, updated_colors}` when the subtree rooted at
`id` is cycle-free, or `{:error, {:cycle_detected, ids}}` as soon as a cycle is
found.

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
  def build(items, opts \\ [])

  def build([], _opts), do: {:ok, []}

  def build(items, opts) when is_list(items) do
    orphan_strategy = Keyword.get(opts, :orphan_strategy, :discard)

    {id_to_node, ordered_ids} = index_items(items)

    case detect_duplicate_ids(items) do
      {:error, _} = err ->
        err

      :ok ->
        children_map = build_children_map(items)
        known_ids = MapSet.new(ordered_ids)

        case detect_cycle(ordered_ids, children_map) do
          {:error, _} = err ->
            err

          :ok ->
            root_ids =
              Enum.filter(ordered_ids, fn id ->
                pid = Map.fetch!(id_to_node, id).parent_id

                cond do
                  is_nil(pid) -> true
                  not MapSet.member?(known_ids, pid) -> orphan_strategy == :raise_to_root
                  true -> false
                end
              end)

            nodes =
              Enum.flat_map(root_ids, fn id ->
                flatten(id, id_to_node, children_map, 0, [])
              end)

            {:ok, nodes}
        end
    end
  end

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