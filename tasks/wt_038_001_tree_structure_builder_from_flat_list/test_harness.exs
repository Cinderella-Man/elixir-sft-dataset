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
end
