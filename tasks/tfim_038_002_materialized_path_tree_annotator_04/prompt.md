# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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
defmodule TreePathsTest do
  use ExUnit.Case, async: false

  defp ids(nodes), do: Enum.map(nodes, & &1.id)

  test "returns empty list for empty input" do
    assert {:ok, []} = TreePaths.build([])
  end

  test "single root has depth 0 and single-element path" do
    assert {:ok, [node]} = TreePaths.build([%{id: 1, parent_id: nil, name: "root"}])
    assert node.id == 1
    assert node.name == "root"
    assert node.depth == 0
    assert node.path == [1]
  end

  test "parent-child emitted in pre-order with accumulating path" do
    # TODO
  end

  test "deep tree accumulates full ancestor path and increasing depth" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 2}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [1, 2, 3]
    assert Enum.map(nodes, & &1.depth) == [0, 1, 2]
    assert Enum.map(nodes, & &1.path) == [[1], [1, 2], [1, 2, 3]]
  end

  test "pre-order visits a whole subtree before the next sibling" do
    # 1 -> 2 -> 4
    #      2 -> 5
    # 1 -> 3
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1},
      %{id: 4, parent_id: 2},
      %{id: 5, parent_id: 2}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [1, 2, 4, 5, 3]
  end

  test "children preserve original input order" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 4, parent_id: 1},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [1, 4, 2, 3]
  end

  test "multiple roots preserve input order" do
    items = [
      %{id: :c, parent_id: nil},
      %{id: :a, parent_id: nil},
      %{id: :b, parent_id: nil}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [:c, :a, :b]
    assert Enum.all?(nodes, &(&1.depth == 0))
  end

  test "all original fields are preserved alongside annotations" do
    items = [
      %{id: "a", parent_id: nil, label: "Alpha", score: 42},
      %{id: "b", parent_id: "a", label: "Beta", score: 7}
    ]

    assert {:ok, [root, child]} = TreePaths.build(items)
    assert root.label == "Alpha" and root.score == 42
    assert child.label == "Beta" and child.score == 7
    assert child.path == ["a", "b"]
  end

  test "orphans are discarded by default" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 99}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [1]
  end

  test "discarding an orphan also drops its whole descendant subtree" do
    # 2 is an orphan (parent 99 is absent); 3 and 4 hang beneath it and must
    # vanish with it rather than being promoted or emitted on their own.
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 99},
      %{id: 3, parent_id: 2},
      %{id: 4, parent_id: 3},
      %{id: 5, parent_id: 1}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [1, 5]
    assert Enum.map(nodes, & &1.path) == [[1], [1, 5]]
    assert {:error, :not_found} = TreePaths.subtree(nodes, 3)
  end

  test ":raise_to_root turns an orphan into a root with its own subtree" do
    items = [
      %{id: 2, parent_id: 99},
      %{id: 3, parent_id: 2}
    ]

    assert {:ok, nodes} = TreePaths.build(items, orphan_strategy: :raise_to_root)
    assert ids(nodes) == [2, 3]

    [orphan, child] = nodes
    assert orphan.depth == 0 and orphan.path == [2]
    assert child.depth == 1 and child.path == [2, 3]
  end

  test "direct cycle returns error" do
    items = [
      %{id: 1, parent_id: 2},
      %{id: 2, parent_id: 1}
    ]

    assert {:error, {:cycle_detected, ids}} = TreePaths.build(items)
    assert Enum.sort(ids) == [1, 2]
  end

  test "indirect cycle returns error" do
    items = [
      %{id: 1, parent_id: 3},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 2}
    ]

    assert {:error, {:cycle_detected, ids}} = TreePaths.build(items)
    assert Enum.sort(ids) == [1, 2, 3]
  end

  test "no false positive on a valid deep tree" do
    items = for i <- 1..20, do: %{id: i, parent_id: if(i == 1, do: nil, else: i - 1)}
    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == Enum.to_list(1..20)
    assert List.last(nodes).depth == 19
  end

  test "subtree returns node plus all descendants in pre-order" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1},
      %{id: 4, parent_id: 2},
      %{id: 5, parent_id: 2}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert {:ok, slice} = TreePaths.subtree(nodes, 2)
    assert ids(slice) == [2, 4, 5]
  end

  test "subtree of a leaf is just the leaf" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert {:ok, [only]} = TreePaths.subtree(nodes, 2)
    assert only.id == 2
  end

  test "subtree returns error for an unknown id" do
    assert {:ok, nodes} = TreePaths.build([%{id: 1, parent_id: nil}])
    assert {:error, :not_found} = TreePaths.subtree(nodes, 999)
  end

  test "cycle unreachable from any root still returns an error" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: :x, parent_id: :y},
      %{id: :y, parent_id: :x}
    ]

    assert {:error, {:cycle_detected, cycle_ids}} = TreePaths.build(items)
    assert Enum.sort(cycle_ids) == [:x, :y]
  end

  test "promoted orphans keep their input position among real roots" do
    items = [
      %{id: :a, parent_id: nil},
      %{id: :orphan, parent_id: :missing},
      %{id: :b, parent_id: nil},
      %{id: :kid, parent_id: :orphan}
    ]

    assert {:ok, nodes} = TreePaths.build(items, orphan_strategy: :raise_to_root)
    assert ids(nodes) == [:a, :orphan, :kid, :b]

    [_a, orphan, kid, _b] = nodes
    assert orphan.depth == 0 and orphan.path == [:orphan]
    assert kid.depth == 1 and kid.path == [:orphan, :kid]
  end

  test "subtree of a root spans grandchildren and excludes other roots" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 2},
      %{id: 4, parent_id: nil},
      %{id: 5, parent_id: 4}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert {:ok, slice} = TreePaths.subtree(nodes, 1)
    assert ids(slice) == [1, 2, 3]
    assert Enum.map(slice, & &1.depth) == [0, 1, 2]
  end
end
```
