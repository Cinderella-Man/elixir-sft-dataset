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
    {:ok, pid} = TreeStream.start_link()
    assert :ok = TreeStream.add(pid, %{id: 1, parent_id: nil})
    assert :ok = TreeStream.add(pid, %{id: 2, parent_id: 1})
    assert :ok = TreeStream.add(pid, %{id: 3, parent_id: 1})

    assert TreeStream.count(pid) == 3
    assert {:ok, [root]} = TreeStream.forest(pid)
    assert root.id == 1
    assert Enum.map(root.children, & &1.id) == [2, 3]
    TreeStream.stop(pid)
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