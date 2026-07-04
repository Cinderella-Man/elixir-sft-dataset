Implement the private `build_subtree/3` function. It takes a node `id`, an
`id_to_node` map (id → the original node map), and a `children_map` (parent id →
ordered list of child ids). It should fetch the node map for `id` from
`id_to_node`, look up that node's child ids in `children_map` (defaulting to an
empty list when the node has no children), and recursively build each child
subtree by calling `build_subtree/3` on every child id in order. Finally, it
returns the original node map with a `:children` key added holding the list of
recursively-built child nodes (so leaf nodes end up with `children: []`).

```elixir
defmodule TreeStream do
  @moduledoc """
  A stateful GenServer that builds a nested forest from node maps arriving
  incrementally and possibly out of order.

  Each node map must have at least `:id` and `:parent_id` (or `nil` for roots).
  Nodes are accumulated in insertion order; `forest/1` computes the nested tree
  on demand, so a child added before its parent is placed correctly once the
  parent arrives.
  """

  use GenServer

  @type id :: term()
  @type node_map :: %{required(:id) => id(), required(:parent_id) => id() | nil}
  @type tree_node :: map()
  @type orphan_strategy :: :discard | :raise_to_root

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the server.

  Supports the `:orphan_strategy` option (`:discard`, the default, or
  `:raise_to_root`), which governs how nodes referencing an absent parent are
  treated when the forest is computed.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    strategy = Keyword.get(opts, :orphan_strategy, :discard)
    GenServer.start_link(__MODULE__, strategy)
  end

  @doc """
  Adds one node.

  Returns `:ok`, or `{:error, {:duplicate_id, id}}` if a node with that id was
  already added (the new item is rejected and the state is left unchanged).
  """
  @spec add(GenServer.server(), node_map()) :: :ok | {:error, {:duplicate_id, id()}}
  def add(server, item), do: GenServer.call(server, {:add, item})

  @doc """
  Adds a list of nodes in order.

  Nodes whose id is already present (from a previous call or earlier in the same
  list) are skipped. Always returns `:ok`.
  """
  @spec add_many(GenServer.server(), [node_map()]) :: :ok
  def add_many(server, items), do: GenServer.call(server, {:add_many, items})

  @doc """
  Computes and returns `{:ok, forest}` from all nodes added so far.

  Each root-level node is the original map with a recursively structured
  `:children` key added. Returns `{:ok, []}` when no nodes have been added, or
  `{:error, {:cycle_detected, ids}}` if the current node set contains a cycle.
  """
  @spec forest(GenServer.server()) ::
          {:ok, [tree_node()]} | {:error, {:cycle_detected, [id()]}}
  def forest(server), do: GenServer.call(server, :forest)

  @doc """
  Returns the number of nodes currently held.
  """
  @spec count(GenServer.server()) :: non_neg_integer()
  def count(server), do: GenServer.call(server, :count)

  @doc """
  Stops the server.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(strategy) do
    {:ok, %{items: [], ids: MapSet.new(), strategy: strategy}}
  end

  @impl true
  def handle_call({:add, item}, _from, state) do
    id = Map.fetch!(item, :id)

    if MapSet.member?(state.ids, id) do
      {:reply, {:error, {:duplicate_id, id}}, state}
    else
      {:reply, :ok, put_item(state, item, id)}
    end
  end

  def handle_call({:add_many, items}, _from, state) do
    new_state =
      Enum.reduce(items, state, fn item, acc ->
        id = Map.fetch!(item, :id)

        if MapSet.member?(acc.ids, id) do
          acc
        else
          put_item(acc, item, id)
        end
      end)

    {:reply, :ok, new_state}
  end

  def handle_call(:forest, _from, state) do
    ordered = Enum.reverse(state.items)
    {:reply, do_build(ordered, state.strategy), state}
  end

  def handle_call(:count, _from, state) do
    {:reply, MapSet.size(state.ids), state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp put_item(state, item, id) do
    %{state | items: [item | state.items], ids: MapSet.put(state.ids, id)}
  end

  defp do_build([], _strategy), do: {:ok, []}

  defp do_build(items, strategy) do
    {id_to_node, ordered_ids} = index_items(items)
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
              not MapSet.member?(known_ids, pid) -> strategy == :raise_to_root
              true -> false
            end
          end)

        forest = Enum.map(root_ids, &build_subtree(&1, id_to_node, children_map))
        {:ok, forest}
    end
  end

  defp index_items(items) do
    {map, ids} =
      Enum.reduce(items, {%{}, []}, fn item, {map, ids} ->
        id = Map.fetch!(item, :id)
        {Map.put(map, id, item), [id | ids]}
      end)

    {map, Enum.reverse(ids)}
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

  defp build_subtree(id, id_to_node, children_map) do
    # TODO
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