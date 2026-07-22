defmodule ReconcilerTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Basic matching
  # ---------------------------------------------------------------------------

  test "records present in both lists appear in :matched" do
    left = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    right = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert length(result.matched) == 2
    assert result.only_in_left == []
    assert result.only_in_right == []
  end

  test "records only in left appear in :only_in_left" do
    left = [%{id: 1}, %{id: 2}]
    right = [%{id: 1}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.only_in_left == [%{id: 2}]
    assert result.only_in_right == []
    assert length(result.matched) == 1
  end

  test "records only in right appear in :only_in_right" do
    left = [%{id: 1}]
    right = [%{id: 1}, %{id: 3}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.only_in_right == [%{id: 3}]
    assert result.only_in_left == []
    assert length(result.matched) == 1
  end

  test "completely disjoint lists produce no matches" do
    left = [%{id: 1}, %{id: 2}]
    right = [%{id: 3}, %{id: 4}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.matched == []
    assert length(result.only_in_left) == 2
    assert length(result.only_in_right) == 2
  end

  test "empty left list" do
    left = []
    right = [%{id: 1}, %{id: 2}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.matched == []
    assert result.only_in_left == []
    assert length(result.only_in_right) == 2
  end

  test "empty right list" do
    left = [%{id: 1}, %{id: 2}]
    right = []

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.matched == []
    assert result.only_in_right == []
    assert length(result.only_in_left) == 2
  end

  test "both lists empty" do
    result = Reconciler.reconcile([], [], key_fields: [:id])
    assert result == %{matched: [], only_in_left: [], only_in_right: []}
  end

  # ---------------------------------------------------------------------------
  # Field-level diff
  # ---------------------------------------------------------------------------

  test "identical matched records have empty differences map" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alice", age: 30}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.differences == %{}
  end

  test "differing fields are reported correctly" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alicia", age: 31}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched

    assert entry.differences == %{
             name: %{left: "Alice", right: "Alicia"},
             age: %{left: 30, right: 31}
           }
  end

  test "matched entry carries full original records regardless of diffs" do
    left = [%{id: 1, name: "Alice", role: "admin"}]
    right = [%{id: 1, name: "Alice", role: "user"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.left == %{id: 1, name: "Alice", role: "admin"}
    assert entry.right == %{id: 1, name: "Alice", role: "user"}
  end

  # ---------------------------------------------------------------------------
  # compare_fields option
  # ---------------------------------------------------------------------------

  test "compare_fields restricts which fields are diffed" do
    left = [%{id: 1, name: "Alice", internal_ref: "old"}]
    right = [%{id: 1, name: "Alice", internal_ref: "new"}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name]
      )

    [entry] = result.matched
    # :internal_ref differs but is excluded from comparison
    assert entry.differences == %{}
  end

  test "compare_fields still diffs the specified fields" do
    left = [%{id: 1, name: "Alice", score: 10}]
    right = [%{id: 1, name: "Bob", score: 10}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name]
      )

    [entry] = result.matched
    assert entry.differences == %{name: %{left: "Alice", right: "Bob"}}
  end

  test "when compare_fields is omitted, all non-key fields are compared" do
    left = [%{id: 1, a: 1, b: 2}]
    right = [%{id: 1, a: 9, b: 2}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert Map.has_key?(entry.differences, :a)
    refute Map.has_key?(entry.differences, :b)
    refute Map.has_key?(entry.differences, :id)
  end

  # ---------------------------------------------------------------------------
  # Composite keys
  # ---------------------------------------------------------------------------

  test "composite key matches only when all key fields are equal" do
    left = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      %{org_id: 1, user_id: 20, name: "Bob"}
    ]

    right = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      # same user_id, different org
      %{org_id: 2, user_id: 10, name: "Charlie"}
    ]

    result = Reconciler.reconcile(left, right, key_fields: [:org_id, :user_id])

    assert length(result.matched) == 1
    [entry] = result.matched
    assert entry.left.name == "Alice"

    # Bob (org 1, user 20)
    assert length(result.only_in_left) == 1
    # Charlie (org 2, user 10)
    assert length(result.only_in_right) == 1
  end

  # ---------------------------------------------------------------------------
  # Missing fields treated as nil
  # ---------------------------------------------------------------------------

  test "a field missing from one record is diffed as nil vs present value" do
    left = [%{id: 1, score: 42}]
    # :score absent
    right = [%{id: 1}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  # ---------------------------------------------------------------------------
  # Mixed scenario (integration)
  # ---------------------------------------------------------------------------

  test "mixed scenario with matches, diffs, and uniques" do
    left = [
      %{id: 1, name: "Alice", status: "active"},
      %{id: 2, name: "Bob", status: "active"},
      %{id: 3, name: "Charlie", status: "inactive"}
    ]

    right = [
      # identical
      %{id: 1, name: "Alice", status: "active"},
      # status differs
      %{id: 2, name: "Bob", status: "inactive"},
      # only in right
      %{id: 4, name: "Diana", status: "active"}
    ]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    # Totals
    assert length(result.matched) == 2
    assert length(result.only_in_left) == 1
    assert length(result.only_in_right) == 1

    # Only-lists
    assert hd(result.only_in_left).id == 3
    assert hd(result.only_in_right).id == 4

    # Matched record with no diff
    alice = Enum.find(result.matched, &(&1.left.id == 1))
    assert alice.differences == %{}

    # Matched record with diff
    bob = Enum.find(result.matched, &(&1.left.id == 2))
    assert bob.differences == %{status: %{left: "active", right: "inactive"}}
  end
end
