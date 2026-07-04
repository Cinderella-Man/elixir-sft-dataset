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
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [1, 2]

    [root, child] = nodes
    assert root.depth == 0 and root.path == [1]
    assert child.depth == 1 and child.path == [1, 2]
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
end