defmodule ReconcilerDuplicateTest do
  use ExUnit.Case, async: false

  test "unique keys reconcile normally with no duplicates" do
    left = [%{id: 1, v: "a"}, %{id: 2, v: "b"}]
    right = [%{id: 1, v: "a"}, %{id: 3, v: "c"}]
    r = Reconciler.reconcile(left, right, key_fields: [:id])

    assert Enum.map(r.matched, & &1.left.id) == [1]
    assert Enum.map(r.only_in_left, & &1.id) == [2]
    assert Enum.map(r.only_in_right, & &1.id) == [3]
    assert r.duplicate_keys == []
  end

  test "duplicate key on left is flagged and excluded from matched" do
    left = [%{id: 1, v: "a"}, %{id: 1, v: "b"}]
    right = [%{id: 1, v: "a"}]
    r = Reconciler.reconcile(left, right, key_fields: [:id])

    assert r.matched == []
    assert r.only_in_left == []
    assert r.only_in_right == []
    assert r.duplicate_keys == [%{key: %{id: 1}, left_count: 2, right_count: 1}]
  end

  test "duplicate key on right is flagged" do
    left = [%{id: 1}]
    right = [%{id: 1}, %{id: 1}]
    r = Reconciler.reconcile(left, right, key_fields: [:id])

    assert r.duplicate_keys == [%{key: %{id: 1}, left_count: 1, right_count: 2}]
    assert r.matched == []
  end

  test "duplicate key present only on one side is still flagged with zero on the other" do
    left = [%{id: 5}, %{id: 5}]
    right = []
    r = Reconciler.reconcile(left, right, key_fields: [:id])

    assert r.duplicate_keys == [%{key: %{id: 5}, left_count: 2, right_count: 0}]
    assert r.only_in_left == []
  end

  test "mix of matched, only, and duplicate keys" do
    left = [
      %{id: 1, v: "x"},
      %{id: 2, v: "y"},
      %{id: 3, v: "d1"},
      %{id: 3, v: "d2"}
    ]

    right = [
      %{id: 1, v: "x"},
      %{id: 4, v: "z"},
      %{id: 3, v: "d3"}
    ]

    r = Reconciler.reconcile(left, right, key_fields: [:id])

    assert Enum.map(r.matched, & &1.left.id) == [1]
    assert Enum.map(r.only_in_left, & &1.id) == [2]
    assert Enum.map(r.only_in_right, & &1.id) == [4]
    assert r.duplicate_keys == [%{key: %{id: 3}, left_count: 2, right_count: 1}]
  end

  test "matched records still carry differences" do
    left = [%{id: 1, v: "a", n: 1}]
    right = [%{id: 1, v: "b", n: 1}]
    r = Reconciler.reconcile(left, right, key_fields: [:id])

    [entry] = r.matched
    assert entry.differences == %{v: %{left: "a", right: "b"}}
  end

  test "identical matched records have empty differences" do
    left = [%{id: 1, v: "a"}]
    right = [%{id: 1, v: "a"}]
    r = Reconciler.reconcile(left, right, key_fields: [:id])

    assert hd(r.matched).differences == %{}
  end

  test "composite duplicate keys produce a composite key map" do
    left = [%{org: 1, uid: 9}, %{org: 1, uid: 9}]
    right = [%{org: 1, uid: 9}]
    r = Reconciler.reconcile(left, right, key_fields: [:org, :uid])

    assert r.duplicate_keys == [%{key: %{org: 1, uid: 9}, left_count: 2, right_count: 1}]
  end

  test "composite keys match exactly for non-duplicates" do
    left = [%{org: 1, uid: 10, name: "Alice"}, %{org: 1, uid: 20, name: "Bob"}]
    right = [%{org: 1, uid: 10, name: "Alice"}, %{org: 2, uid: 10, name: "Charlie"}]
    r = Reconciler.reconcile(left, right, key_fields: [:org, :uid])

    assert length(r.matched) == 1
    assert length(r.only_in_left) == 1
    assert length(r.only_in_right) == 1
    assert r.duplicate_keys == []
  end

  test "compare_fields restricts diffing for matched pairs" do
    left = [%{id: 1, name: "A", ref: "old"}]
    right = [%{id: 1, name: "A", ref: "new"}]
    r = Reconciler.reconcile(left, right, key_fields: [:id], compare_fields: [:name])

    assert hd(r.matched).differences == %{}
  end

  test "missing field diffed as nil for matched pairs" do
    left = [%{id: 1, score: 42}]
    right = [%{id: 1}]
    r = Reconciler.reconcile(left, right, key_fields: [:id])

    assert hd(r.matched).differences == %{score: %{left: 42, right: nil}}
  end

  test "empty inputs yield all-empty buckets" do
    assert Reconciler.reconcile([], [], key_fields: [:id]) ==
             %{matched: [], only_in_left: [], only_in_right: [], duplicate_keys: []}
  end

  test "raises when key_fields missing" do
    assert_raise ArgumentError, fn ->
      Reconciler.reconcile([%{id: 1}], [%{id: 1}], [])
    end
  end
end