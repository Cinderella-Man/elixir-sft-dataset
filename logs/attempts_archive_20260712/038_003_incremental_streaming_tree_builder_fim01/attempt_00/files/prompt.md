# Implement `do_build/2`

Implement the private `do_build/2` function. This is the core forest-building
routine used by the `:forest` GenServer call. It receives `items` — the list of
node maps in **insertion order** (roots and children mixed, possibly out of
order) — and `strategy`, the configured orphan strategy (`:discard` or
`:raise_to_root`). It returns either `{:ok, forest}` or
`{:error, {:cycle_detected, ids}}`.

It must:

1. When `items` is empty, return `{:ok, []}`.
2. Otherwise, build the lookup structures it needs from `items` using the
   existing helpers:
   - `index_items/1` to get `{id_to_node, ordered_ids}`, where `id_to_node` maps
     each id to its original node map and `ordered_ids` lists ids in insertion
     order;
   - `build_children_map/1` to get a map from each parent id to its list of
     child ids (in insertion order);
   - a `MapSet` of the known ids (from `ordered_ids`) so parent references can be
     checked for presence.
3. Run cycle detection with `detect_cycle/2` over `ordered_ids` and the children
   map. If it returns `{:error, _}`, propagate that error unchanged.
4. If there is no cycle, determine the **root ids** by filtering `ordered_ids`
   (preserving insertion order) so a node is a root when:
   - its `parent_id` is `nil`, or
   - its `parent_id` is **not** among the known ids and the strategy is
     `:raise_to_root` (an absent parent under `:discard` means the node is
     dropped, i.e. not a root and not attached anywhere).
   A node whose `parent_id` is present but not a root is left out here (it is
   nested under its parent).
5. Build the forest by mapping each root id through `build_subtree/3`
   (which recursively attaches the `:children` key), and return `{:ok, forest}`.

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

  defp do_build(items, strategy) do
    # TODO
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