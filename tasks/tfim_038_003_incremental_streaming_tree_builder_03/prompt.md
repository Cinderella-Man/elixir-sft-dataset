# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule TreeStreamTest do
  use ExUnit.Case, async: false

  defp collect_ids(nodes) do
    Enum.flat_map(nodes, fn node -> [node.id | collect_ids(node.children)] end)
  end

  test "starts and reports an empty forest" do
    assert {:ok, pid} = TreeStream.start_link()
    assert TreeStream.count(pid) == 0
    assert {:ok, []} = TreeStream.forest(pid)
    TreeStream.stop(pid)
  end

  test "builds a nested tree from incrementally added nodes" do
    # TODO
  end

  test "handles a child added before its parent (out-of-order)" do
    {:ok, pid} = TreeStream.start_link()
    # grandchild first, then child, then root
    assert :ok = TreeStream.add(pid, %{id: 3, parent_id: 2})
    assert :ok = TreeStream.add(pid, %{id: 2, parent_id: 1})
    assert :ok = TreeStream.add(pid, %{id: 1, parent_id: nil})

    assert {:ok, [root]} = TreeStream.forest(pid)
    assert root.id == 1
    assert [%{id: 2, children: [%{id: 3}]}] = root.children
    TreeStream.stop(pid)
  end

  test "root and sibling order follow insertion order, not id order" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: 10, parent_id: nil})
    TreeStream.add(pid, %{id: 1, parent_id: nil})
    TreeStream.add(pid, %{id: 5, parent_id: 10})
    TreeStream.add(pid, %{id: 2, parent_id: 10})

    assert {:ok, [first, second]} = TreeStream.forest(pid)
    assert first.id == 10
    assert second.id == 1
    assert Enum.map(first.children, & &1.id) == [5, 2]
    TreeStream.stop(pid)
  end

  test "duplicate add is rejected and leaves state unchanged" do
    {:ok, pid} = TreeStream.start_link()
    assert :ok = TreeStream.add(pid, %{id: 1, parent_id: nil, v: :first})
    assert {:error, {:duplicate_id, 1}} = TreeStream.add(pid, %{id: 1, parent_id: nil, v: :second})

    assert TreeStream.count(pid) == 1
    assert {:ok, [root]} = TreeStream.forest(pid)
    assert root.v == :first
    TreeStream.stop(pid)
  end

  test "add_many adds all and skips duplicates" do
    {:ok, pid} = TreeStream.start_link()

    assert :ok =
             TreeStream.add_many(pid, [
               %{id: 1, parent_id: nil},
               %{id: 2, parent_id: 1},
               %{id: 1, parent_id: nil},
               %{id: 3, parent_id: 1}
             ])

    assert TreeStream.count(pid) == 3
    assert {:ok, [root]} = TreeStream.forest(pid)
    assert Enum.map(root.children, & &1.id) == [2, 3]
    TreeStream.stop(pid)
  end

  test "preserves all original fields" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: "a", parent_id: nil, label: "Alpha", score: 42})
    TreeStream.add(pid, %{id: "b", parent_id: "a", label: "Beta", score: 7})

    assert {:ok, [root]} = TreeStream.forest(pid)
    assert root.label == "Alpha" and root.score == 42
    assert [child] = root.children
    assert child.label == "Beta" and child.score == 7
    TreeStream.stop(pid)
  end

  test "orphans are discarded by default" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: 1, parent_id: nil})
    TreeStream.add(pid, %{id: 2, parent_id: 99})

    assert {:ok, roots} = TreeStream.forest(pid)
    assert collect_ids(roots) == [1]
    TreeStream.stop(pid)
  end

  test ":raise_to_root promotes orphans to roots" do
    {:ok, pid} = TreeStream.start_link(orphan_strategy: :raise_to_root)
    TreeStream.add(pid, %{id: 1, parent_id: nil})
    TreeStream.add(pid, %{id: 2, parent_id: 99})
    TreeStream.add(pid, %{id: 3, parent_id: 2})

    assert {:ok, roots} = TreeStream.forest(pid)
    all = collect_ids(roots)
    assert Enum.sort(all) == [1, 2, 3]
    orphan_root = Enum.find(roots, &(&1.id == 2))
    assert [%{id: 3}] = orphan_root.children
    TreeStream.stop(pid)
  end

  test "detects a direct cycle in the current node set" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: 1, parent_id: 2})
    TreeStream.add(pid, %{id: 2, parent_id: 1})

    assert {:error, {:cycle_detected, ids}} = TreeStream.forest(pid)
    assert Enum.sort(ids) == [1, 2]
    TreeStream.stop(pid)
  end

  test "detects an indirect cycle" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: 1, parent_id: 3})
    TreeStream.add(pid, %{id: 2, parent_id: 1})
    TreeStream.add(pid, %{id: 3, parent_id: 2})

    assert {:error, {:cycle_detected, ids}} = TreeStream.forest(pid)
    assert Enum.sort(ids) == [1, 2, 3]
    TreeStream.stop(pid)
  end

  test "forest reflects state as it grows across multiple queries" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: 1, parent_id: nil})
    assert {:ok, [%{children: []}]} = TreeStream.forest(pid)

    TreeStream.add(pid, %{id: 2, parent_id: 1})
    assert {:ok, [%{children: [%{id: 2}]}]} = TreeStream.forest(pid)
    TreeStream.stop(pid)
  end
end
```
