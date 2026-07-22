defmodule BagReconcilerTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Basic (single-occurrence) behaviour
  # ---------------------------------------------------------------------------

  test "single-occurrence keys pair up one-to-one" do
    left = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    right = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])

    assert length(result.pairs) == 2
    assert result.unmatched_left == []
    assert result.unmatched_right == []
    assert result.duplicate_keys == []
    assert Enum.all?(result.pairs, &(&1.differences == %{}))
    assert Enum.all?(result.pairs, &(&1.index == 0))
  end

  test "keys present on only one side become unmatched entries carrying key and record" do
    left = [%{id: 1}, %{id: 2, name: "Bob"}]
    right = [%{id: 1}, %{id: 3, name: "Carol"}]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])

    assert length(result.pairs) == 1
    assert result.unmatched_left == [%{key: %{id: 2}, record: %{id: 2, name: "Bob"}}]
    assert result.unmatched_right == [%{key: %{id: 3}, record: %{id: 3, name: "Carol"}}]
  end

  test "both lists empty" do
    result = BagReconciler.reconcile_bags([], [], key_fields: [:id])

    assert result.pairs == []
    assert result.unmatched_left == []
    assert result.unmatched_right == []
    assert result.duplicate_keys == []
  end

  test "empty right list sends every left record to unmatched_left" do
    left = [%{id: 1}, %{id: 2}]

    result = BagReconciler.reconcile_bags(left, [], key_fields: [:id])

    assert result.pairs == []
    assert length(result.unmatched_left) == 2
    assert result.unmatched_right == []
  end

  # ---------------------------------------------------------------------------
  # Bag / duplicate-key pairing
  # ---------------------------------------------------------------------------

  test "duplicate occurrences on both sides are paired in input order by index" do
    left = [
      %{id: 1, amount: 10},
      %{id: 1, amount: 20}
    ]

    right = [
      %{id: 1, amount: 10},
      %{id: 1, amount: 99}
    ]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])

    assert length(result.pairs) == 2
    assert result.unmatched_left == []
    assert result.unmatched_right == []

    [first, second] = Enum.sort_by(result.pairs, & &1.index)

    assert first.index == 0
    assert first.left == %{id: 1, amount: 10}
    assert first.right == %{id: 1, amount: 10}
    assert first.differences == %{}

    assert second.index == 1
    assert second.left == %{id: 1, amount: 20}
    assert second.right == %{id: 1, amount: 99}
    assert second.differences == %{amount: %{left: 20, right: 99}}
  end

  test "surplus left occurrences (the later ones) land in unmatched_left" do
    left = [
      %{id: 1, seq: "a"},
      %{id: 1, seq: "b"},
      %{id: 1, seq: "c"}
    ]

    right = [%{id: 1, seq: "a"}]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])

    assert length(result.pairs) == 1
    [pair] = result.pairs
    assert pair.index == 0
    assert pair.left == %{id: 1, seq: "a"}

    assert Enum.map(result.unmatched_left, & &1.record) == [
             %{id: 1, seq: "b"},
             %{id: 1, seq: "c"}
           ]

    assert result.unmatched_right == []
  end

  test "surplus right occurrences land in unmatched_right" do
    left = [%{id: 7, v: 1}]
    right = [%{id: 7, v: 1}, %{id: 7, v: 2}]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])

    assert length(result.pairs) == 1
    assert result.unmatched_left == []
    assert Enum.map(result.unmatched_right, & &1.record) == [%{id: 7, v: 2}]
  end

  # ---------------------------------------------------------------------------
  # duplicate_keys reporting
  # ---------------------------------------------------------------------------

  test "duplicate_keys reports counts for keys repeated on at least one side" do
    left = [%{id: 1}, %{id: 1}, %{id: 1}, %{id: 2}]
    right = [%{id: 1}, %{id: 2}]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])

    assert result.duplicate_keys == [%{key: %{id: 1}, left_count: 3, right_count: 1}]
  end

  test "duplicate_keys can report a key absent from one side with a zero count" do
    left = []
    right = [%{id: 5}, %{id: 5}]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])

    assert result.duplicate_keys == [%{key: %{id: 5}, left_count: 0, right_count: 2}]
    assert length(result.unmatched_right) == 2
  end

  test "keys occurring at most once per side are not reported as duplicates" do
    left = [%{id: 1}, %{id: 2}]
    right = [%{id: 2}, %{id: 3}]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])

    assert result.duplicate_keys == []
  end

  # ---------------------------------------------------------------------------
  # Diffing
  # ---------------------------------------------------------------------------

  test "compare_fields restricts which fields are diffed" do
    left = [%{id: 1, name: "Alice", note: "old"}]
    right = [%{id: 1, name: "Alice", note: "new"}]

    result =
      BagReconciler.reconcile_bags(left, right, key_fields: [:id], compare_fields: [:name])

    [pair] = result.pairs
    assert pair.differences == %{}
    # full original records are still carried
    assert pair.left == %{id: 1, name: "Alice", note: "old"}
    assert pair.right == %{id: 1, name: "Alice", note: "new"}
  end

  test "without compare_fields every non-key field is compared" do
    left = [%{id: 1, a: 1, b: 2}]
    right = [%{id: 1, a: 9, b: 2}]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])

    [pair] = result.pairs
    assert Map.has_key?(pair.differences, :a)
    refute Map.has_key?(pair.differences, :b)
    refute Map.has_key?(pair.differences, :id)
  end

  test "a compare field missing from one record is diffed as nil" do
    left = [%{id: 1, score: 42}]
    right = [%{id: 1}]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])

    [pair] = result.pairs
    assert pair.differences == %{score: %{left: 42, right: nil}}
  end

  # ---------------------------------------------------------------------------
  # Composite keys
  # ---------------------------------------------------------------------------

  test "composite key groups only records equal on all key fields" do
    left = [
      %{org_id: 1, user_id: 10, role: "admin"},
      %{org_id: 1, user_id: 10, role: "owner"},
      %{org_id: 2, user_id: 10, role: "user"}
    ]

    right = [
      %{org_id: 1, user_id: 10, role: "admin"}
    ]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:org_id, :user_id])

    assert length(result.pairs) == 1
    [pair] = result.pairs
    assert pair.key == %{org_id: 1, user_id: 10}

    unmatched = Enum.map(result.unmatched_left, & &1.record)
    assert length(unmatched) == 2
    assert %{org_id: 2, user_id: 10, role: "user"} in unmatched
    assert %{org_id: 1, user_id: 10, role: "owner"} in unmatched
  end

  # ---------------------------------------------------------------------------
  # key_counts/2
  # ---------------------------------------------------------------------------

  test "key_counts counts occurrences per key" do
    records = [%{id: 1}, %{id: 1}, %{id: 2}]

    assert BagReconciler.key_counts(records, [:id]) == %{%{id: 1} => 2, %{id: 2} => 1}
  end

  test "key_counts works with composite keys and an empty list" do
    records = [
      %{org_id: 1, user_id: 10},
      %{org_id: 1, user_id: 11},
      %{org_id: 1, user_id: 10}
    ]

    assert BagReconciler.key_counts(records, [:org_id, :user_id]) == %{
             %{org_id: 1, user_id: 10} => 2,
             %{org_id: 1, user_id: 11} => 1
           }

    assert BagReconciler.key_counts([], [:id]) == %{}
  end

  test "a missing key field contributes nil to the key map" do
    records = [%{id: 1}, %{name: "x"}]

    assert BagReconciler.key_counts(records, [:id]) == %{%{id: 1} => 1, %{id: nil} => 1}
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  test "missing or invalid :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      BagReconciler.reconcile_bags([], [], [])
    end

    assert_raise ArgumentError, fn ->
      BagReconciler.reconcile_bags([], [], key_fields: [])
    end

    assert_raise ArgumentError, fn ->
      BagReconciler.reconcile_bags([], [], key_fields: "id")
    end
  end

  # ---------------------------------------------------------------------------
  # Integration
  # ---------------------------------------------------------------------------

  test "mixed scenario: duplicates, surplus, diffs and unique keys" do
    left = [
      %{id: 1, amt: 100},
      %{id: 1, amt: 200},
      %{id: 2, amt: 50},
      %{id: 3, amt: 10}
    ]

    right = [
      %{id: 1, amt: 100},
      %{id: 2, amt: 55},
      %{id: 4, amt: 1}
    ]

    result = BagReconciler.reconcile_bags(left, right, key_fields: [:id])

    assert length(result.pairs) == 2
    assert length(result.unmatched_left) == 2
    assert length(result.unmatched_right) == 1

    [id2] = Enum.filter(result.pairs, &(&1.key == %{id: 2}))
    assert id2.differences == %{amt: %{left: 50, right: 55}}

    assert result.duplicate_keys == [%{key: %{id: 1}, left_count: 2, right_count: 1}]

    unmatched_left_records = Enum.map(result.unmatched_left, & &1.record)
    assert %{id: 1, amt: 200} in unmatched_left_records
    assert %{id: 3, amt: 10} in unmatched_left_records

    assert Enum.map(result.unmatched_right, & &1.record) == [%{id: 4, amt: 1}]
  end
end
