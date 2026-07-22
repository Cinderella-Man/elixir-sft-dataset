defmodule ReconcilerTest do
  use ExUnit.Case, async: false

  defp matched_for(result, key_map) do
    Enum.find(result.matched, fn e -> e.key == key_map end)
  end

  defp only_left_for(result, key_map) do
    Enum.find(result.only_in_left, fn e -> e.key == key_map end)
  end

  defp dup_for(result, key_map, side) do
    Enum.find(result.duplicates, fn e -> e.key == key_map and e.side == side end)
  end

  # ---------------------------------------------------------------------------
  # Grouping and matching
  # ---------------------------------------------------------------------------

  test "a key on both sides (once each) goes into :matched with single-element lists" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "Alicia"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    entry = matched_for(result, %{id: 1})
    assert entry.left == [%{id: 1, name: "Alice"}]
    assert entry.right == [%{id: 1, name: "Alicia"}]
    assert result.duplicates == []
  end

  test "key_map contains exactly the key fields" do
    left = [%{id: 7, extra: "x"}]
    right = [%{id: 7, extra: "y"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])
    entry = matched_for(result, %{id: 7})
    assert entry.key == %{id: 7}
  end

  test "keys only on the left are grouped in :only_in_left" do
    left = [%{id: 1, v: "a"}, %{id: 2, v: "b"}]
    right = [%{id: 1, v: "a"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    entry = only_left_for(result, %{id: 2})
    assert entry.records == [%{id: 2, v: "b"}]
    assert result.only_in_right == []
  end

  test "keys only on the right are grouped in :only_in_right" do
    left = [%{id: 1}]
    right = [%{id: 1}, %{id: 3, v: "c"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert length(result.only_in_right) == 1
    [entry] = result.only_in_right
    assert entry.key == %{id: 3}
    assert entry.records == [%{id: 3, v: "c"}]
  end

  test "both lists empty yields empty everything" do
    result = Reconciler.reconcile([], [], key_fields: [:id])
    assert result == %{matched: [], only_in_left: [], only_in_right: [], duplicates: []}
  end

  # ---------------------------------------------------------------------------
  # Duplicate detection
  # ---------------------------------------------------------------------------

  test "duplicate key on the left is reported with count and collected into matched" do
    left = [%{id: 1, tag: "a"}, %{id: 1, tag: "b"}]
    right = [%{id: 1, tag: "c"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    entry = matched_for(result, %{id: 1})
    assert length(entry.left) == 2
    assert length(entry.right) == 1

    dup = dup_for(result, %{id: 1}, :left)
    assert dup.count == 2
    # right side is not duplicated
    assert dup_for(result, %{id: 1}, :right) == nil
  end

  test "a key duplicated on both sides produces two duplicate entries" do
    left = [%{id: 1, s: "l1"}, %{id: 1, s: "l2"}]
    right = [%{id: 1, s: "r1"}, %{id: 1, s: "r2"}, %{id: 1, s: "r3"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    left_dup = dup_for(result, %{id: 1}, :left)
    right_dup = dup_for(result, %{id: 1}, :right)
    assert left_dup.count == 2
    assert right_dup.count == 3
    assert length(result.duplicates) == 2
  end

  test "duplicates are reported even for side-exclusive keys" do
    left = [%{id: 9, s: "a"}, %{id: 9, s: "b"}]
    right = []

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    entry = only_left_for(result, %{id: 9})
    assert length(entry.records) == 2

    dup = dup_for(result, %{id: 9}, :left)
    assert dup.count == 2
  end

  test "unique keys produce no duplicate entries" do
    left = [%{id: 1}, %{id: 2}]
    right = [%{id: 1}, %{id: 2}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])
    assert result.duplicates == []
    assert length(result.matched) == 2
  end

  # ---------------------------------------------------------------------------
  # Order preservation within a group
  # ---------------------------------------------------------------------------

  test "records within a group keep input order" do
    left = [
      %{id: 1, seq: 1},
      %{id: 1, seq: 2},
      %{id: 1, seq: 3}
    ]

    right = [%{id: 1, seq: 99}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])
    entry = matched_for(result, %{id: 1})
    assert Enum.map(entry.left, & &1.seq) == [1, 2, 3]
  end

  # ---------------------------------------------------------------------------
  # Composite keys
  # ---------------------------------------------------------------------------

  test "composite key groups only when all key fields are equal" do
    left = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      %{org_id: 1, user_id: 20, name: "Bob"}
    ]

    right = [
      %{org_id: 1, user_id: 10, name: "Alice2"},
      %{org_id: 2, user_id: 10, name: "Charlie"}
    ]

    result = Reconciler.reconcile(left, right, key_fields: [:org_id, :user_id])

    matched = matched_for(result, %{org_id: 1, user_id: 10})
    assert length(matched.left) == 1
    assert length(matched.right) == 1

    assert only_left_for(result, %{org_id: 1, user_id: 20}) != nil
    assert length(result.only_in_left) == 1
    assert length(result.only_in_right) == 1
  end

  test "composite key_map carries all key fields" do
    left = [%{org_id: 5, user_id: 50, x: 1}]
    right = [%{org_id: 5, user_id: 50, x: 2}]

    result = Reconciler.reconcile(left, right, key_fields: [:org_id, :user_id])
    entry = matched_for(result, %{org_id: 5, user_id: 50})
    assert entry.key == %{org_id: 5, user_id: 50}
  end

  # ---------------------------------------------------------------------------
  # Integration
  # ---------------------------------------------------------------------------

  test "mixed scenario with matches, uniques, and duplicates" do
    left = [
      %{id: 1, r: "l"},
      %{id: 2, r: "l"},
      %{id: 2, r: "l"},
      %{id: 3, r: "l"}
    ]

    right = [
      %{id: 1, r: "r"},
      %{id: 2, r: "r"},
      %{id: 4, r: "r"}
    ]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    # keys 1 and 2 are on both sides
    assert length(result.matched) == 2
    # key 3 only on left
    assert length(result.only_in_left) == 1
    assert only_left_for(result, %{id: 3}) != nil
    # key 4 only on right
    assert length(result.only_in_right) == 1

    two = matched_for(result, %{id: 2})
    assert length(two.left) == 2
    assert length(two.right) == 1

    assert dup_for(result, %{id: 2}, :left).count == 2
    assert length(result.duplicates) == 1
  end
end
