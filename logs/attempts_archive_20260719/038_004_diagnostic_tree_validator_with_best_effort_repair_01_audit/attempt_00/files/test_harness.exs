defmodule TreeValidatorTest do
  use ExUnit.Case, async: false

  defp collect_ids(nodes) do
    Enum.flat_map(nodes, fn node -> [node.id | collect_ids(node.children)] end)
  end

  defp issue(issues, type), do: Enum.find(issues, &(&1.type == type))

  test "empty input is ok with empty forest" do
    assert {:ok, []} = TreeValidator.build([])
  end

  test "clean input returns {:ok, forest}" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 1}
    ]

    assert {:ok, [root]} = TreeValidator.build(items)
    assert root.id == 1
    assert Enum.map(root.children, & &1.id) == [2, 3]
  end

  test "preserves original fields on a clean build" do
    items = [
      %{id: "a", parent_id: nil, label: "Alpha"},
      %{id: "b", parent_id: "a", label: "Beta"}
    ]

    assert {:ok, [root]} = TreeValidator.build(items)
    assert root.label == "Alpha"
    assert [child] = root.children
    assert child.label == "Beta"
  end

  test "duplicate ids: first kept, later dropped, reported" do
    items = [
      %{id: 1, parent_id: nil, v: :first},
      %{id: 2, parent_id: 1},
      %{id: 1, parent_id: nil, v: :second}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert [root] = forest
    assert root.v == :first
    assert Enum.map(root.children, & &1.id) == [2]

    dup = issue(issues, :duplicate_id)
    assert dup.ids == [1]
  end

  test "missing :parent_id key is treated as a root and reported" do
    items = [
      %{id: 1, parent_id: nil},
      # no :parent_id key at all
      %{id: 2},
      %{id: 3, parent_id: 2}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    ids = collect_ids(forest)
    assert Enum.sort(ids) == [1, 2, 3]

    node2 = Enum.find(forest, &(&1.id == 2))
    assert [%{id: 3}] = node2.children

    mp = issue(issues, :missing_parent_id)
    assert mp.ids == [2]
  end

  test "orphan is raised to root and reported" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 99},
      %{id: 3, parent_id: 2}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert Enum.sort(collect_ids(forest)) == [1, 2, 3]

    orphan_root = Enum.find(forest, &(&1.id == 2))
    assert [%{id: 3}] = orphan_root.children

    orphan = issue(issues, :orphan)
    assert orphan.ids == [2]
  end

  test "direct cycle: nodes dropped, cycle reported" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 3},
      %{id: 3, parent_id: 2}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert collect_ids(forest) == [1]

    cyc = issue(issues, :cycle)
    assert Enum.sort(cyc.ids) == [2, 3]
  end

  test "indirect cycle is detected and its nodes removed" do
    items = [
      %{id: 1, parent_id: 3},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 2}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert forest == []

    cyc = issue(issues, :cycle)
    assert Enum.sort(cyc.ids) == [1, 2, 3]
  end

  test "a node pointing into a removed cycle becomes an orphan" do
    items = [
      %{id: 1, parent_id: nil},
      # cycle 2 <-> 3
      %{id: 2, parent_id: 3},
      %{id: 3, parent_id: 2},
      # 4 references a cycle node that gets removed
      %{id: 4, parent_id: 3}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert Enum.sort(collect_ids(forest)) == [1, 4]

    cyc = issue(issues, :cycle)
    assert Enum.sort(cyc.ids) == [2, 3]

    orphan = issue(issues, :orphan)
    assert orphan.ids == [4]
  end

  test "multiple issue types are ordered dup, missing_parent, orphan, cycle" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 1, parent_id: nil},
      %{id: 2},
      %{id: 3, parent_id: 88},
      %{id: 4, parent_id: 5},
      %{id: 5, parent_id: 4}
    ]

    assert {:issues, _forest, issues} = TreeValidator.build(items)
    types = Enum.map(issues, & &1.type)
    assert types == [:duplicate_id, :missing_parent_id, :orphan, :cycle]
  end

  test "no false positive on a valid deep tree" do
    items = for i <- 1..20, do: %{id: i, parent_id: if(i == 1, do: nil, else: i - 1)}
    assert {:ok, [root]} = TreeValidator.build(items)
    assert collect_ids([root]) == Enum.to_list(1..20)
  end

  test "two disjoint cycles are reported as separate entries" do
    items = [
      %{id: 1, parent_id: 2},
      %{id: 2, parent_id: 1},
      %{id: 3, parent_id: 4},
      %{id: 4, parent_id: 3}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert forest == []

    cycles = Enum.filter(issues, &(&1.type == :cycle))
    assert length(cycles) == 2

    all_cycle_ids = cycles |> Enum.flat_map(& &1.ids) |> Enum.sort()
    assert all_cycle_ids == [1, 2, 3, 4]
  end

  test "duplicate ids are reported once, ordered by first appearance in the input" do
    items = [
      %{id: :b, parent_id: nil, v: :b_first},
      %{id: :a, parent_id: nil, v: :a_first},
      %{id: :a, parent_id: nil, v: :a_second},
      %{id: :b, parent_id: nil, v: :b_second}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert Enum.map(forest, & &1.id) == [:b, :a]
    assert Enum.map(forest, & &1.v) == [:b_first, :a_first]

    assert [%{ids: ids}] = Enum.filter(issues, &(&1.type == :duplicate_id))
    assert ids == [:b, :a]
  end

  test "combined issues still yield a forest containing every repaired node" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 1, parent_id: nil},
      %{id: 2},
      %{id: 3, parent_id: 88},
      %{id: 4, parent_id: 5},
      %{id: 5, parent_id: 4},
      %{id: 6, parent_id: 2},
      %{id: 7, parent_id: 4}
    ]

    assert {:issues, forest, _issues} = TreeValidator.build(items)
    assert Enum.map(forest, & &1.id) == [1, 2, 3, 7]
    assert Enum.sort(collect_ids(forest)) == [1, 2, 3, 6, 7]

    node2 = Enum.find(forest, &(&1.id == 2))
    assert Enum.map(node2.children, & &1.id) == [6]
  end

  test "root and sibling order follows input order even with orphan roots" do
    items = [
      %{id: :x, parent_id: :ghost},
      %{id: 3, parent_id: nil},
      %{id: 30, parent_id: 3},
      %{id: 1, parent_id: nil},
      %{id: 5, parent_id: 3},
      %{id: 3, parent_id: nil}
    ]

    assert {:issues, forest, _issues} = TreeValidator.build(items)
    assert Enum.map(forest, & &1.id) == [:x, 3, 1]

    node3 = Enum.find(forest, &(&1.id == 3))
    assert Enum.map(node3.children, & &1.id) == [30, 5]
  end

  test "several nodes lacking :parent_id collapse into one entry in input order" do
    items = [
      %{id: 4},
      %{id: 1, parent_id: nil},
      %{id: 2},
      %{id: 3, parent_id: 4},
      %{id: 0}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert [%{ids: ids}] = Enum.filter(issues, &(&1.type == :missing_parent_id))
    assert ids == [4, 2, 0]

    assert Enum.map(forest, & &1.id) == [4, 1, 2, 0]
    assert [%{id: 3}] = Enum.find(forest, &(&1.id == 4)).children
  end

  test "multiple orphans are reported as a single entry with all ids" do
    items = [
      %{id: 1, parent_id: :nope},
      %{id: 2, parent_id: nil},
      %{id: 3, parent_id: "gone"},
      %{id: 4, parent_id: 3}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert [%{ids: ids}] = Enum.filter(issues, &(&1.type == :orphan))
    assert ids == [1, 3]

    assert Enum.map(forest, & &1.id) == [1, 2, 3]
    assert [%{id: 4}] = Enum.find(forest, &(&1.id == 3)).children
  end

  test "repaired forest nodes keep original fields and leaves carry empty children" do
    items = [
      %{id: "root", parent_id: "missing", tag: :kept},
      %{id: "leaf", parent_id: "root", tag: :leaf}
    ]

    assert {:issues, [root], _issues} = TreeValidator.build(items)
    assert root.tag == :kept
    assert root.parent_id == "missing"

    assert [leaf] = root.children
    assert leaf.tag == :leaf
    assert leaf.children == []
  end
end
