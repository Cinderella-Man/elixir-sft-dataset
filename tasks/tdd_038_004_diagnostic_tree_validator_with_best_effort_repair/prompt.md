# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

```elixir
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

  test "root and sibling order follow input order, not id order" do
    items = [
      %{id: 3, parent_id: nil},
      %{id: 30, parent_id: 3},
      %{id: 1, parent_id: nil},
      %{id: 10, parent_id: 1},
      %{id: 2, parent_id: nil},
      %{id: 9, parent_id: 3}
    ]

    assert {:ok, forest} = TreeValidator.build(items)
    assert Enum.map(forest, & &1.id) == [3, 1, 2]

    [three, one, _two] = forest
    assert Enum.map(three.children, & &1.id) == [30, 9]
    assert Enum.map(one.children, & &1.id) == [10]
  end

  test "raised orphan and missing-parent roots keep their input positions" do
    items = [
      # orphan: parent 99 is not in the node set, so it is raised to a root
      %{id: 10, parent_id: 99},
      %{id: 1, parent_id: nil},
      # no :parent_id key at all, so it is treated as a root
      %{id: 20},
      %{id: 5, parent_id: 1}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert Enum.map(forest, & &1.id) == [10, 1, 20]

    one = Enum.find(forest, &(&1.id == 1))
    assert Enum.map(one.children, & &1.id) == [5]

    assert issue(issues, :orphan).ids == [10]
    assert issue(issues, :missing_parent_id).ids == [20]
  end

  test "root order after deduplication and cycle removal follows input order" do
    items = [
      %{id: 4, parent_id: nil},
      # cycle 7 <-> 8, both removed from the forest
      %{id: 7, parent_id: 8},
      %{id: 8, parent_id: 7},
      %{id: 2, parent_id: nil},
      # later duplicate of 4 is dropped; the first occurrence keeps its position
      %{id: 4, parent_id: nil},
      %{id: 1, parent_id: nil}
    ]

    assert {:issues, forest, issues} = TreeValidator.build(items)
    assert Enum.map(forest, & &1.id) == [4, 2, 1]

    assert issue(issues, :duplicate_id).ids == [4]
    assert Enum.sort(issue(issues, :cycle).ids) == [7, 8]
  end
end
```

Send back the implementation only — one file, no tests.
