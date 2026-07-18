# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `index_items` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `TreePaths` that converts a flat list of maps into a
**flat, pre-order annotated list** — a "materialized path" representation instead of a
nested tree. This is the same domain as a tree builder, but the output shape is different:
rather than nesting children inside parents, every node is annotated with its position in
the hierarchy.

Each input item is a map with at least these two fields:
- `:id` — a unique identifier (any term: integer, string, atom)
- `:parent_id` — the id of the parent node, or `nil` if this node is a root

I need these functions in the public API:

- `TreePaths.build(items, opts \\ [])` — takes the flat list and returns
  `{:ok, nodes}` where `nodes` is a **flat list in pre-order DFS traversal order**
  (each root, then all of that root's descendants depth-first, before moving to the
  next root). Each element is the original map with two extra keys added:
  - `:depth` — an integer; root nodes have depth `0`, their children `1`, and so on.
  - `:path` — a list of ids from the root down to and including this node
    (so a root's path is `[its_id]`, and a grandchild's is `[root_id, parent_id, id]`).

  If the input is empty, return `{:ok, []}`. Returns
  `{:error, {:cycle_detected, ids}}` if a cycle is found, where `ids` is the list of
  node ids involved in the cycle.

- `TreePaths.subtree(nodes, id)` — given the annotated list returned by `build/1` and an
  id, return `{:ok, slice}` where `slice` is the node with that id followed by all of its
  descendants, in pre-order (i.e. every node whose `:path` contains `id`). Returns
  `{:error, :not_found}` if no node with that id is present in `nodes`.

The `build/1` function must support this option:
- `:orphan_strategy` — what to do when a node's `parent_id` points to an id that doesn't
  exist in the list. Accepted values:
  - `:discard` (default) — silently drop orphan nodes (and their descendants) from output
  - `:raise_to_root` — treat orphans as root nodes (depth `0`, path `[id]`)

Order rules: root nodes appear in their original input order; the children of any parent
appear in the original input order those items appeared in the list. All original fields
must be preserved on each node in addition to the new `:depth` and `:path` keys.

Cycle detection must work for direct cycles (A → B → A) as well as indirect ones
(A → B → C → A), and must not false-positive on valid deep trees.

Do not use any external dependencies — only the Elixir / Erlang standard library.
Give me the complete module in a single file.

## The module with `index_items` missing

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
    # TODO
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

Give me only the complete implementation of `index_items` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
