# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
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
  @type node_map :: %{
          required(:id) => id(),
          required(:parent_id) => id() | nil,
          optional(atom()) => term()
        }
  @type tree_node :: %{
          required(:id) => id(),
          required(:parent_id) => id() | nil,
          required(:children) => [tree_node()],
          optional(atom()) => term()
        }
  @type forest :: [tree_node()]
  @type orphan_strategy :: :discard | :raise_to_root
  @type build_opt :: {:orphan_strategy, orphan_strategy()}
  @type build_result ::
          {:ok, forest()}
          | {:error, {:cycle_detected, [id()]}}
          | {:error, {:duplicate_ids, [id()]}}

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
    - `{:error, {:duplicate_ids, ids}}` when any id appears more than once in
      `items`; `ids` lists the duplicated ids.
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
      {:error, _} = err ->
        err

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
                  is_nil(pid) ->
                    true

                  not MapSet.member?(known_ids, pid) ->
                    orphan_strategy == :raise_to_root

                  true ->
                    false
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
```

## Test harness — implement the `# TODO` test

```elixir
defmodule TreeBuilderTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Recursively collect all ids in DFS order to assert structure.
  defp collect_ids(nodes) do
    Enum.flat_map(nodes, fn node ->
      [node.id | collect_ids(node.children)]
    end)
  end

  # ---------------------------------------------------------------------------
  # Empty / trivial input
  # ---------------------------------------------------------------------------

  test "returns empty forest for empty input" do
    assert {:ok, []} = TreeBuilder.build([])
  end

  test "single root node with no children" do
    item = %{id: 1, parent_id: nil, name: "root"}
    assert {:ok, [node]} = TreeBuilder.build([item])
    assert node.id == 1
    assert node.name == "root"
    assert node.children == []
  end

  # ---------------------------------------------------------------------------
  # Basic hierarchy
  # ---------------------------------------------------------------------------

  test "simple parent-child relationship" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert root.id == 1
    assert [child] = root.children
    assert child.id == 2
    assert child.children == []
  end

  test "three-level deep tree" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 2}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert root.id == 1
    assert [level2] = root.children
    assert level2.id == 2
    assert [level3] = level2.children
    assert level3.id == 3
    assert level3.children == []
  end

  test "node with multiple children preserves input order" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1},
      %{id: 4, parent_id: 1}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert Enum.map(root.children, & &1.id) == [2, 3, 4]
  end

  test "all original fields are preserved on nodes" do
    items = [
      %{id: "a", parent_id: nil, label: "Alpha", score: 42},
      %{id: "b", parent_id: "a", label: "Beta", score: 7}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert root.label == "Alpha"
    assert root.score == 42
    assert [child] = root.children
    assert child.label == "Beta"
    assert child.score == 7
  end

  # ---------------------------------------------------------------------------
  # Multiple roots
  # ---------------------------------------------------------------------------

  test "multiple root nodes are returned" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: nil},
      %{id: 3, parent_id: nil}
    ]

    assert {:ok, roots} = TreeBuilder.build(items)
    assert Enum.map(roots, & &1.id) == [1, 2, 3]
    assert Enum.all?(roots, &(&1.children == []))
  end

  test "multiple roots each with their own subtrees" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 10, parent_id: nil},
      %{id: 11, parent_id: 10},
      %{id: 12, parent_id: 10}
    ]

    assert {:ok, [root1, root2]} = TreeBuilder.build(items)

    assert root1.id == 1
    assert [%{id: 2}] = root1.children

    assert root2.id == 10
    assert Enum.map(root2.children, & &1.id) == [11, 12]
  end

  test "roots preserve their input order" do
    items = [
      %{id: :c, parent_id: nil},
      %{id: :a, parent_id: nil},
      %{id: :b, parent_id: nil}
    ]

    assert {:ok, roots} = TreeBuilder.build(items)
    assert Enum.map(roots, & &1.id) == [:c, :a, :b]
  end

  # ---------------------------------------------------------------------------
  # Cycle detection
  # ---------------------------------------------------------------------------

  test "direct cycle A -> B -> A returns error" do
    items = [
      %{id: 1, parent_id: 2},
      %{id: 2, parent_id: 1}
    ]

    assert {:error, {:cycle_detected, ids}} = TreeBuilder.build(items)
    assert is_list(ids)
    assert 1 in ids
    assert 2 in ids
  end

  test "indirect cycle A -> B -> C -> A returns error" do
    items = [
      %{id: 1, parent_id: 3},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 2}
    ]

    assert {:error, {:cycle_detected, ids}} = TreeBuilder.build(items)
    assert is_list(ids)
    assert Enum.sort(ids) == [1, 2, 3]
  end

  test "no false positive on a valid deep tree" do
    items = for i <- 1..20, do: %{id: i, parent_id: if(i == 1, do: nil, else: i - 1)}
    assert {:ok, [root]} = TreeBuilder.build(items)
    assert collect_ids([root]) == Enum.to_list(1..20)
  end

  test "no false positive on a wide flat tree (many siblings)" do
    items =
      [%{id: 0, parent_id: nil}] ++
        for(i <- 1..50, do: %{id: i, parent_id: 0})

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert length(root.children) == 50
  end

  # ---------------------------------------------------------------------------
  # Orphan handling
  # ---------------------------------------------------------------------------

  test "orphans are discarded by default" do
    items = [
      %{id: 1, parent_id: nil},
      # 99 does not exist
      %{id: 2, parent_id: 99}
    ]

    assert {:ok, roots} = TreeBuilder.build(items)
    all_ids = collect_ids(roots)
    assert 1 in all_ids
    refute 2 in all_ids
  end

  test "orphans are discarded with explicit :discard option" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 99}
    ]

    assert {:ok, roots} = TreeBuilder.build(items, orphan_strategy: :discard)
    refute 2 in collect_ids(roots)
  end

  test ":raise_to_root attaches orphans as root nodes" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 99}
    ]

    assert {:ok, roots} = TreeBuilder.build(items, orphan_strategy: :raise_to_root)
    all_ids = collect_ids(roots)
    assert 1 in all_ids
    assert 2 in all_ids
  end

  test ":raise_to_root orphan carries its own children" do
    items = [
      # orphan
      %{id: 2, parent_id: 99},
      # child of orphan
      %{id: 3, parent_id: 2}
    ]

    assert {:ok, roots} = TreeBuilder.build(items, orphan_strategy: :raise_to_root)
    orphan_root = Enum.find(roots, &(&1.id == 2))
    assert orphan_root != nil
    assert [%{id: 3}] = orphan_root.children
  end

  test "multiple orphans all raised to root" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: :missing},
      %{id: 3, parent_id: :also_missing}
    ]

    assert {:ok, roots} = TreeBuilder.build(items, orphan_strategy: :raise_to_root)
    ids = Enum.map(roots, & &1.id) |> MapSet.new()
    assert MapSet.equal?(ids, MapSet.new([1, 2, 3]))
  end

  # ---------------------------------------------------------------------------
  # Mixed / complex scenarios
  # ---------------------------------------------------------------------------

  test "complex tree: two roots, mixed depths, correct structure" do
    # Tree A:  1 -> 2 -> 4
    #               2 -> 5
    #          1 -> 3
    # Tree B: 10 -> 11
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1},
      %{id: 4, parent_id: 2},
      %{id: 5, parent_id: 2},
      %{id: 10, parent_id: nil},
      %{id: 11, parent_id: 10}
    ]

    assert {:ok, [root_a, root_b]} = TreeBuilder.build(items)

    assert root_a.id == 1
    assert length(root_a.children) == 2
    [child2, child3] = root_a.children
    assert child2.id == 2
    assert child3.id == 3
    assert Enum.map(child2.children, & &1.id) == [4, 5]
    assert child3.children == []

    assert root_b.id == 10
    assert [%{id: 11, children: []}] = root_b.children
  end

  test "input given in child-first order still builds correctly" do
    items = [
      %{id: 3, parent_id: 2},
      %{id: 2, parent_id: 1},
      %{id: 1, parent_id: nil}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert root.id == 1
    assert [%{id: 2, children: [%{id: 3}]}] = root.children
  end

  test "string ids work the same as integer ids" do
    items = [
      %{id: "root", parent_id: nil},
      %{id: "child", parent_id: "root"}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert root.id == "root"
    assert [%{id: "child"}] = root.children
  end

  test "a duplicated id is rejected with the duplicate list" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 1, parent_id: nil}
    ]

    assert {:error, {:duplicate_ids, [1]}} = TreeBuilder.build(items)
  end

  test "cycle inside an otherwise valid input errors with only the cycle ids" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 10, parent_id: 11},
      %{id: 11, parent_id: 10}
    ]

    assert {:error, {:cycle_detected, ids}} = TreeBuilder.build(items)
    assert Enum.sort(ids) == [10, 11]
  end

  test "every duplicated id is reported exactly once when several ids repeat" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 2, parent_id: 1}
    ]

    assert {:error, {:duplicate_ids, ids}} = TreeBuilder.build(items)
    assert Enum.sort(ids) == [1, 2]
  end

  test "raised orphans and real roots together follow original input order" do
    items = [
      %{id: :orphan_a, parent_id: :missing},
      %{id: :root_b, parent_id: nil},
      %{id: :orphan_c, parent_id: :gone},
      %{id: :root_d, parent_id: nil}
    ]

    opts = [orphan_strategy: :raise_to_root]
    assert {:ok, roots} = TreeBuilder.build(items, opts)
    assert Enum.map(roots, & &1.id) == [:orphan_a, :root_b, :orphan_c, :root_d]
  end

  test "sibling order is preserved when children of different parents interleave" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: nil},
      %{id: :a1, parent_id: 1},
      %{id: :b1, parent_id: 2},
      %{id: :a2, parent_id: 1},
      %{id: :b2, parent_id: 2},
      %{id: :a3, parent_id: 1}
    ]

    assert {:ok, [r1, r2]} = TreeBuilder.build(items)
    assert Enum.map(r1.children, & &1.id) == [:a1, :a2, :a3]
    assert Enum.map(r2.children, & &1.id) == [:b1, :b2]
  end

  test "diamond-shaped branches listed deepest-first are not reported as a cycle" do
    items = [
      %{id: 4, parent_id: 2},
      %{id: 5, parent_id: 3},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1},
      %{id: 1, parent_id: nil}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert collect_ids([root]) == [1, 2, 4, 3, 5]
  end

  test "an indirect cycle is still detected when orphans are raised to root" do
    # TODO
  end
end
```
