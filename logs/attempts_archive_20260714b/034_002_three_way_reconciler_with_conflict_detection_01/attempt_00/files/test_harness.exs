defmodule ThreeWayReconcilerTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Clean merges
  # ---------------------------------------------------------------------------

  test "unchanged records merge to the base value" do
    base = [%{id: 1, name: "Alice", role: "user"}]
    left = [%{id: 1, name: "Alice", role: "user"}]
    right = [%{id: 1, name: "Alice", role: "user"}]

    result = ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])

    assert result.conflicts == []
    assert result.unpaired == []
    [entry] = result.merged
    assert entry.merged == %{id: 1, name: "Alice", role: "user"}
  end

  test "a change made only on the left is applied" do
    base = [%{id: 1, name: "Alice", role: "user"}]
    left = [%{id: 1, name: "Alicia", role: "user"}]
    right = [%{id: 1, name: "Alice", role: "user"}]

    result = ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])

    [entry] = result.merged
    assert entry.merged == %{id: 1, name: "Alicia", role: "user"}
    assert result.conflicts == []
  end

  test "a change made only on the right is applied" do
    base = [%{id: 1, name: "Alice", role: "user"}]
    left = [%{id: 1, name: "Alice", role: "user"}]
    right = [%{id: 1, name: "Alice", role: "admin"}]

    result = ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])

    [entry] = result.merged
    assert entry.merged == %{id: 1, name: "Alice", role: "admin"}
    assert result.conflicts == []
  end

  test "identical changes on both sides do not conflict" do
    base = [%{id: 1, status: "active"}]
    left = [%{id: 1, status: "archived"}]
    right = [%{id: 1, status: "archived"}]

    result = ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])

    assert result.conflicts == []
    [entry] = result.merged
    assert entry.merged == %{id: 1, status: "archived"}
  end

  test "independent changes to different fields merge cleanly" do
    base = [%{id: 1, name: "Alice", role: "user"}]
    left = [%{id: 1, name: "Alicia", role: "user"}]
    right = [%{id: 1, name: "Alice", role: "admin"}]

    result = ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])

    assert result.conflicts == []
    [entry] = result.merged
    assert entry.merged == %{id: 1, name: "Alicia", role: "admin"}
  end

  # ---------------------------------------------------------------------------
  # Conflicts
  # ---------------------------------------------------------------------------

  test "divergent changes to the same field conflict" do
    base = [%{id: 1, name: "Alice"}]
    left = [%{id: 1, name: "Bob"}]
    right = [%{id: 1, name: "Carol"}]

    result = ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])

    assert result.merged == []
    [entry] = result.conflicts
    assert entry.conflicts == %{name: %{base: "Alice", left: "Bob", right: "Carol"}}
    assert entry.base == %{id: 1, name: "Alice"}
    assert entry.left == %{id: 1, name: "Bob"}
    assert entry.right == %{id: 1, name: "Carol"}
  end

  test "only conflicting fields appear in the conflict map" do
    base = [%{id: 1, name: "Alice", role: "user"}]
    left = [%{id: 1, name: "Bob", role: "admin"}]
    right = [%{id: 1, name: "Carol", role: "user"}]

    result = ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])

    [entry] = result.conflicts
    # :role changed only on the left -> not a conflict; only :name conflicts.
    assert entry.conflicts == %{name: %{base: "Alice", left: "Bob", right: "Carol"}}
  end

  # ---------------------------------------------------------------------------
  # Unpaired keys
  # ---------------------------------------------------------------------------

  test "a key missing from one side is unpaired" do
    base = [%{id: 1, v: 1}]
    left = [%{id: 1, v: 1}]
    right = []

    result = ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])

    assert result.merged == []
    assert result.conflicts == []
    [entry] = result.unpaired
    assert entry.key == %{id: 1}
    assert entry.sides == %{base: %{id: 1, v: 1}, left: %{id: 1, v: 1}, right: nil}
  end

  test "a key added only on the right is unpaired" do
    base = []
    left = []
    right = [%{id: 9, v: 5}]

    result = ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])

    [entry] = result.unpaired
    assert entry.key == %{id: 9}
    assert entry.sides.base == nil
    assert entry.sides.left == nil
    assert entry.sides.right == %{id: 9, v: 5}
  end

  # ---------------------------------------------------------------------------
  # compare_fields
  # ---------------------------------------------------------------------------

  test "compare_fields restricts which fields are reconciled" do
    base = [%{id: 1, name: "Alice", internal: "x"}]
    left = [%{id: 1, name: "Alice", internal: "y"}]
    right = [%{id: 1, name: "Alice", internal: "z"}]

    result =
      ThreeWayReconciler.reconcile(base, left, right,
        key_fields: [:id],
        compare_fields: [:name]
      )

    # :internal diverges but is not compared -> clean merge keeping base's :internal.
    assert result.conflicts == []
    [entry] = result.merged
    assert entry.merged == %{id: 1, name: "Alice", internal: "x"}
  end

  # ---------------------------------------------------------------------------
  # Missing fields as nil
  # ---------------------------------------------------------------------------

  test "a field added on one side (absent in base) merges as a clean add" do
    base = [%{id: 1, x: 1}]
    left = [%{id: 1, x: 1, y: 2}]
    right = [%{id: 1, x: 1}]

    result = ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])

    assert result.conflicts == []
    [entry] = result.merged
    assert entry.merged == %{id: 1, x: 1, y: 2}
  end

  # ---------------------------------------------------------------------------
  # Composite keys
  # ---------------------------------------------------------------------------

  test "composite key requires all key fields to match" do
    base = [%{org_id: 1, user_id: 10, role: "user"}]
    left = [%{org_id: 1, user_id: 10, role: "admin"}]
    right = [%{org_id: 2, user_id: 10, role: "user"}]

    result =
      ThreeWayReconciler.reconcile(base, left, right, key_fields: [:org_id, :user_id])

    # (1,10) is present in base+left but not right -> unpaired.
    # (2,10) is present only in right -> unpaired.
    assert result.merged == []
    assert result.conflicts == []
    assert length(result.unpaired) == 2
  end

  # ---------------------------------------------------------------------------
  # Errors
  # ---------------------------------------------------------------------------

  test "missing :key_fields raises" do
    assert_raise ArgumentError, fn ->
      ThreeWayReconciler.reconcile([], [], [], [])
    end
  end

  # ---------------------------------------------------------------------------
  # Integration
  # ---------------------------------------------------------------------------

  test "mixed scenario with merges, conflicts, and unpaired keys" do
    base = [
      %{id: 1, name: "Alice", role: "user"},
      %{id: 2, name: "Bob", role: "user"},
      %{id: 3, name: "Carol", role: "user"},
      %{id: 4, name: "Dave", role: "user"}
    ]

    left = [
      %{id: 1, name: "Alice", role: "user"},
      %{id: 2, name: "Bobby", role: "user"},
      %{id: 3, name: "Carol", role: "admin"},
      %{id: 5, name: "Eve", role: "user"}
    ]

    right = [
      %{id: 1, name: "Alice", role: "user"},
      %{id: 2, name: "Robert", role: "user"},
      %{id: 3, name: "Caroline", role: "user"},
      %{id: 4, name: "Dave", role: "user"}
    ]

    result = ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])

    # id 1: unchanged -> merged
    # id 2: name conflict (Bobby vs Robert) -> conflict
    # id 3: role changed left, name changed right -> clean merge
    # id 4: present in base+right, absent in left -> unpaired
    # id 5: present only in left -> unpaired
    ids_merged = Enum.map(result.merged, & &1.base.id) |> Enum.sort()
    assert ids_merged == [1, 3]

    id3 = Enum.find(result.merged, &(&1.base.id == 3))
    assert id3.merged == %{id: 3, name: "Caroline", role: "admin"}

    assert [conflict] = result.conflicts
    assert conflict.base.id == 2
    assert conflict.conflicts == %{name: %{base: "Bob", left: "Bobby", right: "Robert"}}

    unpaired_ids =
      result.unpaired
      |> Enum.map(& &1.key.id)
      |> Enum.sort()

    assert unpaired_ids == [4, 5]
  end
end