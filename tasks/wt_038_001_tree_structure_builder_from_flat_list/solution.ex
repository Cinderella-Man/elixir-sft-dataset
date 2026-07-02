defmodule TreeBuilder do
  @moduledoc """
  Converts a flat list of maps into a nested tree (forest) structure.

  Each input map must have at least:
    - `:id`        — a unique identifier (any term)
    - `:parent_id` — the id of the parent node, or `nil` for root nodes

  ## Example

      iex> items = [
      ...>   %{id: 1, parent_id: nil,  name: "root"},
      ...>   %{id: 2, parent_id: 1,    name: "child"},
      ...>   %{id: 3, parent_id: 2,    name: "grandchild"},
      ...> ]
      iex> {:ok, [root]} = TreeBuilder.build(items)
      iex> root.name
      "root"
      iex> [child] = root.children
      iex> child.name
      "child"
      iex> [grandchild] = child.children
      iex> grandchild.name
      "grandchild"
  """

  @type id :: term()
  @type node_map :: %{required(:id) => id(), required(:parent_id) => id() | nil, optional(atom()) => term()}
  @type tree_node :: %{required(:id) => id(), required(:parent_id) => id() | nil, required(:children) => [tree_node()], optional(atom()) => term()}
  @type forest :: [tree_node()]
  @type orphan_strategy :: :discard | :raise_to_root
  @type build_opt :: {:orphan_strategy, orphan_strategy()}
  @type build_result :: {:ok, forest()} | {:error, {:cycle_detected, [id()]}}

  @doc """
  Builds a forest (list of root trees) from a flat list of node maps.

  ## Options

    - `:orphan_strategy` — behaviour for nodes whose `parent_id` references a
      non-existent id.
      - `:discard` (default) — orphan nodes are silently dropped.
      - `:raise_to_root` — orphan nodes are treated as additional root nodes.

  ## Return values

    - `{:ok, forest}` on success (empty list when `items` is empty).
    - `{:error, {:cycle_detected, ids}}` when a cycle is detected; `ids` is the
      list of node ids that form the cycle.
  """
  @spec build([node_map()], [build_opt()]) :: build_result()
  def build(items, opts \\ [])

  def build([], _opts), do: {:ok, []}

  def build(items, opts) when is_list(items) do
    orphan_strategy = Keyword.get(opts, :orphan_strategy, :discard)

    # Index nodes by id, preserving insertion order via a list of ids.
    {id_to_node, ordered_ids} = index_items(items)

    # Validate: duplicate ids are detected early.
    case detect_duplicate_ids(items) do
      {:error, _} = err -> err
      :ok ->
        # Build a parent_id → [child_id] map (children in original order).
        children_map = build_children_map(items)

        # Determine which nodes are "known" ids.
        known_ids = MapSet.new(ordered_ids)

        # Detect cycles using DFS on the children graph before we build anything.
        case detect_cycle(ordered_ids, children_map) do
          {:error, _} = err ->
            err

          :ok ->
            # Identify root nodes: parent_id is nil, OR parent_id is unknown
            # (orphan handling) — depending on strategy.
            root_ids =
              ordered_ids
              |> Enum.filter(fn id ->
                node = Map.fetch!(id_to_node, id)
                pid = node.parent_id

                cond do
                  is_nil(pid) -> true
                  not MapSet.member?(known_ids, pid) ->
                    orphan_strategy == :raise_to_root
                  true -> false
                end
              end)

            forest =
              Enum.map(root_ids, fn id ->
                build_subtree(id, id_to_node, children_map)
              end)

            {:ok, forest}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Index items into a map of id → node and a list of ids in original order.
  @spec index_items([node_map()]) :: {%{id() => node_map()}, [id()]}
  defp index_items(items) do
    Enum.reduce(items, {%{}, []}, fn item, {map, ids} ->
      id = Map.fetch!(item, :id)
      {Map.put(map, id, item), [id | ids]}
    end)
    |> then(fn {map, ids} -> {map, Enum.reverse(ids)} end)
  end

  @spec detect_duplicate_ids([node_map()]) :: :ok | {:error, {:duplicate_ids, [id()]}}
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

  # Build a map of parent_id → [child_id, ...] in original order.
  @spec build_children_map([node_map()]) :: %{id() => [id()]}
  defp build_children_map(items) do
    # We want children in the same order as the original list, so we walk
    # forward and append (via reversal at the end).
    items
    |> Enum.reduce(%{}, fn item, acc ->
      pid = item.parent_id

      if is_nil(pid) do
        acc
      else
        Map.update(acc, pid, [item.id], fn existing -> existing ++ [item.id] end)
      end
    end)
  end

  # Recursively build a tree node, attaching children.
  @spec build_subtree(id(), %{id() => node_map()}, %{id() => [id()]}) :: tree_node()
  defp build_subtree(id, id_to_node, children_map) do
    node = Map.fetch!(id_to_node, id)
    child_ids = Map.get(children_map, id, [])

    children =
      Enum.map(child_ids, fn child_id ->
        build_subtree(child_id, id_to_node, children_map)
      end)

    Map.put(node, :children, children)
  end

  # ---------------------------------------------------------------------------
  # Cycle detection — iterative DFS (white/grey/black colouring)
  # ---------------------------------------------------------------------------
  # Colours:
  #   :white — not yet visited
  #   :grey  — currently in the DFS stack (ancestor path)
  #   :black — fully explored, no cycle through this node

  @spec detect_cycle([id()], %{id() => [id()]}) ::
          :ok | {:error, {:cycle_detected, [id()]}}
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

  # DFS from `id`. `stack` is the list of ancestor ids (for cycle reporting).
  @spec dfs(id(), %{id() => [id()]}, map(), [id()]) ::
          {:ok, map()} | {:error, {:cycle_detected, [id()]}}
  defp dfs(id, children_map, colors, stack) do
    colors = Map.put(colors, id, :grey)
    stack = [id | stack]

    child_ids = Map.get(children_map, id, [])

    result =
      Enum.reduce_while(child_ids, {:ok, colors}, fn child_id, {:ok, acc_colors} ->
        case Map.get(acc_colors, child_id) do
          :grey ->
            # Back-edge → cycle found.
            # Extract the cycle portion from the stack.
            cycle = extract_cycle(child_id, [child_id | stack])
            {:halt, {:error, {:cycle_detected, cycle}}}

          :white ->
            case dfs(child_id, children_map, acc_colors, stack) do
              {:ok, new_colors} -> {:cont, {:ok, new_colors}}
              {:error, _} = err -> {:halt, err}
            end

          :black ->
            # Already fully explored; safe to skip.
            {:cont, {:ok, acc_colors}}

          nil ->
            # child_id not in our color map → orphan reference, skip.
            {:cont, {:ok, acc_colors}}
        end
      end)

    case result do
      {:ok, colors} ->
        {:ok, Map.put(colors, id, :black)}

      {:error, _} = err ->
        err
    end
  end

  # Given the back-edge target `cycle_root` and the current DFS path (newest
  # first), return the ids that form the cycle in top-down order.
  @spec extract_cycle(id(), [id()]) :: [id()]
  defp extract_cycle(cycle_root, path) do
    # `path` is [cycle_root, current_node, ..., cycle_root_ancestor, ...]
    # Reverse so it reads oldest-first, drop nodes before the cycle entry
    # point, then deduplicate so cycle_root doesn't appear at both ends.
    path
    |> Enum.reverse()
    |> Enum.drop_while(fn id -> id != cycle_root end)
    |> Enum.uniq()
    |> then(fn
      [] -> [cycle_root]
      slice -> slice
    end)
  end
end
