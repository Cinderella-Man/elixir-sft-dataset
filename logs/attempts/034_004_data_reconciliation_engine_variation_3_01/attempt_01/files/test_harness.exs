defmodule ConcurrentReconcilerTest do
  use ExUnit.Case, async: false

  defp sort_by_id(list), do: Enum.sort_by(list, &record_id/1)
  defp record_id(%{left: l}), do: l.id
  defp record_id(%{id: id}), do: id

  # ---------------------------------------------------------------------------
  # Basic behaviour (parity with a sequential reconciler)
  # ---------------------------------------------------------------------------

  test "records present in both lists appear in :matched" do
    left = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    right = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    result = ConcurrentReconciler.reconcile(left, right, key_fields: [:id])

    assert length(result.matched) == 2
    assert result.only_in_left == []
    assert result.only_in_right == []
  end

  test "records only in left / right are partitioned correctly" do
    left = [%{id: 1}, %{id: 2}]
    right = [%{id: 1}, %{id: 3}]

    result = ConcurrentReconciler.reconcile(left, right, key_fields: [:id])

    assert length(result.matched) == 1
    assert result.only_in_left == [%{id: 2}]
    assert result.only_in_right == [%{id: 3}]
  end

  test "differing fields are reported" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alicia", age: 31}]

    result = ConcurrentReconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched

    assert entry.differences == %{
             name: %{left: "Alice", right: "Alicia"},
             age: %{left: 30, right: 31}
           }
  end

  test "identical matched records have empty differences" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "Alice"}]

    result = ConcurrentReconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.differences == %{}
    assert entry.left == %{id: 1, name: "Alice"}
    assert entry.right == %{id: 1, name: "Alice"}
  end

  test "compare_fields restricts the diff" do
    left = [%{id: 1, name: "Alice", internal: "old"}]
    right = [%{id: 1, name: "Alice", internal: "new"}]

    result =
      ConcurrentReconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name]
      )

    [entry] = result.matched
    assert entry.differences == %{}
  end

  test "a field missing from one record is diffed as nil" do
    left = [%{id: 1, score: 42}]
    right = [%{id: 1}]

    result = ConcurrentReconciler.reconcile(left, right, key_fields: [:id])

    [entry] = result.matched
    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  test "composite key matches only when all fields are equal" do
    left = [%{org_id: 1, user_id: 10, name: "Alice"}, %{org_id: 1, user_id: 20, name: "Bob"}]
    right = [%{org_id: 1, user_id: 10, name: "Alice"}, %{org_id: 2, user_id: 10, name: "Carol"}]

    result =
      ConcurrentReconciler.reconcile(left, right, key_fields: [:org_id, :user_id])

    assert length(result.matched) == 1
    assert length(result.only_in_left) == 1
    assert length(result.only_in_right) == 1
  end

  # ---------------------------------------------------------------------------
  # Concurrency-specific behaviour
  # ---------------------------------------------------------------------------

  test "result is independent of :max_concurrency" do
    left = for i <- 1..200, do: %{id: i, v: i}
    right = for i <- 1..200, do: %{id: i, v: i + rem(i, 3)}

    seq = ConcurrentReconciler.reconcile(left, right, key_fields: [:id], max_concurrency: 1)
    par = ConcurrentReconciler.reconcile(left, right, key_fields: [:id], max_concurrency: 8)

    assert sort_by_id(seq.matched) == sort_by_id(par.matched)
    assert sort_by_id(seq.only_in_left) == sort_by_id(par.only_in_left)
    assert sort_by_id(seq.only_in_right) == sort_by_id(par.only_in_right)
  end

  test "large dataset reconciles correctly under concurrency" do
    left = for i <- 1..1_000, do: %{id: i, v: i}

    right =
      for i <- 1..1_000 do
        if rem(i, 2) == 0, do: %{id: i, v: i}, else: %{id: i, v: i + 1}
      end

    result = ConcurrentReconciler.reconcile(left, right, key_fields: [:id], max_concurrency: 16)

    assert length(result.matched) == 1_000
    assert result.only_in_left == []
    assert result.only_in_right == []

    changed = Enum.filter(result.matched, &(&1.differences != %{}))
    unchanged = Enum.filter(result.matched, &(&1.differences == %{}))

    # Odd ids differ, even ids are identical.
    assert length(changed) == 500
    assert length(unchanged) == 500
    assert Enum.all?(changed, &(rem(&1.left.id, 2) == 1))
  end

  test "invalid :max_concurrency raises" do
    assert_raise ArgumentError, fn ->
      ConcurrentReconciler.reconcile([%{id: 1}], [%{id: 1}], key_fields: [:id], max_concurrency: 0)
    end

    assert_raise ArgumentError, fn ->
      ConcurrentReconciler.reconcile([%{id: 1}], [%{id: 1}],
        key_fields: [:id],
        max_concurrency: :lots
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  test "empty inputs" do
    assert ConcurrentReconciler.reconcile([], [], key_fields: [:id]) ==
             %{matched: [], only_in_left: [], only_in_right: []}
  end

  test "missing :key_fields raises" do
    assert_raise ArgumentError, fn ->
      ConcurrentReconciler.reconcile([], [], [])
    end
  end
end