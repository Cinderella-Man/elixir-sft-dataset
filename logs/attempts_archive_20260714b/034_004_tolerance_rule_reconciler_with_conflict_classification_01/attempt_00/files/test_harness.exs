defmodule TolerantReconcilerTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # diff_pair/3 — statuses
  # ---------------------------------------------------------------------------

  test "identical maps yield :identical and an empty diff map" do
    assert TolerantReconciler.diff_pair(%{a: 1, b: "x"}, %{a: 1, b: "x"}, []) ==
             {:identical, %{}}
  end

  test "fields without a rule default to :exact and any difference is a conflict" do
    {status, diff} = TolerantReconciler.diff_pair(%{a: 1}, %{a: 2}, [])

    assert status == :conflict
    assert diff == %{a: %{left: 1, right: 2, status: :conflict}}
  end

  test "numeric rule tolerates a difference within the tolerance" do
    {status, diff} =
      TolerantReconciler.diff_pair(%{amount: 100.0}, %{amount: 100.004},
        rules: [amount: {:numeric, 0.01}]
      )

    assert status == :within_tolerance
    assert %{amount: %{left: 100.0, right: 100.004, status: :within_tolerance}} = diff
  end

  test "numeric rule flags a difference beyond the tolerance as a conflict" do
    {status, diff} =
      TolerantReconciler.diff_pair(%{amount: 100}, %{amount: 105},
        rules: %{amount: {:numeric, 1}}
      )

    assert status == :conflict
    assert diff == %{amount: %{left: 100, right: 105, status: :conflict}}
  end

  test "numeric rule conflicts when a value is not a number" do
    {status, diff} =
      TolerantReconciler.diff_pair(%{amount: 100}, %{amount: nil},
        rules: [amount: {:numeric, 1000}]
      )

    assert status == :conflict
    assert diff == %{amount: %{left: 100, right: nil, status: :conflict}}
  end

  test "case_insensitive rule tolerates case and surrounding whitespace" do
    {status, diff} =
      TolerantReconciler.diff_pair(%{name: "  Alice "}, %{name: "alice"},
        rules: [name: :case_insensitive]
      )

    assert status == :within_tolerance
    assert %{name: %{left: "  Alice ", right: "alice", status: :within_tolerance}} = diff
  end

  test "case_insensitive rule conflicts on genuinely different strings" do
    {status, _diff} =
      TolerantReconciler.diff_pair(%{name: "Alice"}, %{name: "Bob"},
        rules: [name: :case_insensitive]
      )

    assert status == :conflict
  end

  test "case_insensitive rule conflicts when a value is not a binary" do
    {status, diff} =
      TolerantReconciler.diff_pair(%{name: "alice"}, %{name: nil},
        rules: [name: :case_insensitive]
      )

    assert status == :conflict
    assert diff == %{name: %{left: "alice", right: nil, status: :conflict}}
  end

  test "an :exact rule stated explicitly still conflicts on any difference" do
    {status, _diff} =
      TolerantReconciler.diff_pair(%{code: "A"}, %{code: "a"}, rules: [code: :exact])

    assert status == :conflict
  end

  test "a pair with tolerable and conflicting differences is a :conflict overall" do
    {status, diff} =
      TolerantReconciler.diff_pair(
        %{amount: 10.0, name: "Alice", city: "Paris"},
        %{amount: 10.001, name: "ALICE", city: "Berlin"},
        rules: [amount: {:numeric, 0.01}, name: :case_insensitive]
      )

    assert status == :conflict
    assert diff.amount.status == :within_tolerance
    assert diff.name.status == :within_tolerance
    assert diff.city.status == :conflict
  end

  # ---------------------------------------------------------------------------
  # diff_pair/3 — field selection
  # ---------------------------------------------------------------------------

  test "ignore_fields excludes fields from comparison entirely" do
    {status, diff} =
      TolerantReconciler.diff_pair(%{id: 1, note: "old"}, %{id: 1, note: "new"},
        ignore_fields: [:note]
      )

    assert status == :identical
    assert diff == %{}
  end

  test "a field present in only one map is read as nil and diffed" do
    {status, diff} = TolerantReconciler.diff_pair(%{a: 1, b: 2}, %{a: 1}, [])

    assert status == :conflict
    assert diff == %{b: %{left: 2, right: nil, status: :conflict}}
  end

  # ---------------------------------------------------------------------------
  # reconcile_all/3
  # ---------------------------------------------------------------------------

  test "matched pairs are bucketed by status and key fields are never compared" do
    left = [
      %{id: 1, amount: 10.0, name: "Alice"},
      %{id: 2, amount: 20.0, name: "bob"},
      %{id: 3, amount: 30.0, name: "Carol"}
    ]

    right = [
      %{id: 1, amount: 10.0, name: "Alice"},
      %{id: 2, amount: 20.002, name: "Bob "},
      %{id: 3, amount: 99.0, name: "Carol"}
    ]

    result =
      TolerantReconciler.reconcile_all(left, right,
        key_fields: [:id],
        rules: [amount: {:numeric, 0.01}, name: :case_insensitive]
      )

    assert [identical] = result.identical
    assert identical.key == %{id: 1}
    assert identical.differences == %{}

    assert [tolerated] = result.within_tolerance
    assert tolerated.key == %{id: 2}
    assert tolerated.left == %{id: 2, amount: 20.0, name: "bob"}
    assert tolerated.right == %{id: 2, amount: 20.002, name: "Bob "}
    assert tolerated.differences.amount.status == :within_tolerance
    assert tolerated.differences.name.status == :within_tolerance

    assert [conflict] = result.conflicts
    assert conflict.key == %{id: 3}
    assert conflict.differences.amount.status == :conflict

    assert result.only_in_left == []
    assert result.only_in_right == []
  end

  test "keys present on only one side are reported as raw records" do
    left = [%{id: 1, v: 1}, %{id: 2, v: 2}]
    right = [%{id: 1, v: 1}, %{id: 3, v: 3}]

    result = TolerantReconciler.reconcile_all(left, right, key_fields: [:id])

    assert result.only_in_left == [%{id: 2, v: 2}]
    assert result.only_in_right == [%{id: 3, v: 3}]
    assert length(result.identical) == 1
    assert result.within_tolerance == []
    assert result.conflicts == []
  end

  test "extra ignore_fields are excluded on top of the key fields" do
    left = [%{id: 1, name: "Alice", synced_at: "monday"}]
    right = [%{id: 1, name: "Alice", synced_at: "tuesday"}]

    result =
      TolerantReconciler.reconcile_all(left, right,
        key_fields: [:id],
        ignore_fields: [:synced_at]
      )

    assert [entry] = result.identical
    assert entry.differences == %{}
    # full original records are still carried
    assert entry.left == %{id: 1, name: "Alice", synced_at: "monday"}
    assert entry.right == %{id: 1, name: "Alice", synced_at: "tuesday"}
  end

  test "composite keys only match when every key field agrees" do
    left = [
      %{org_id: 1, user_id: 10, role: "admin"},
      %{org_id: 1, user_id: 20, role: "user"}
    ]

    right = [
      %{org_id: 1, user_id: 10, role: "admin"},
      %{org_id: 2, user_id: 10, role: "user"}
    ]

    result = TolerantReconciler.reconcile_all(left, right, key_fields: [:org_id, :user_id])

    assert [entry] = result.identical
    assert entry.key == %{org_id: 1, user_id: 10}
    assert length(result.only_in_left) == 1
    assert length(result.only_in_right) == 1
  end

  test "duplicate keys on a side: the last record in the input list wins" do
    left = [%{id: 1, v: "first"}, %{id: 1, v: "last"}]
    right = [%{id: 1, v: "last"}]

    result = TolerantReconciler.reconcile_all(left, right, key_fields: [:id])

    assert [entry] = result.identical
    assert entry.left == %{id: 1, v: "last"}
  end

  test "empty inputs produce five empty buckets" do
    result = TolerantReconciler.reconcile_all([], [], key_fields: [:id])

    assert result == %{
             identical: [],
             within_tolerance: [],
             conflicts: [],
             only_in_left: [],
             only_in_right: []
           }
  end

  test "missing or invalid :key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      TolerantReconciler.reconcile_all([], [], [])
    end

    assert_raise ArgumentError, fn ->
      TolerantReconciler.reconcile_all([], [], key_fields: [])
    end

    assert_raise ArgumentError, fn ->
      TolerantReconciler.reconcile_all([], [], key_fields: :id)
    end
  end

  # ---------------------------------------------------------------------------
  # summary/1
  # ---------------------------------------------------------------------------

  test "summary counts every bucket and totals the matched pairs" do
    left = [
      %{id: 1, amount: 1.0},
      %{id: 2, amount: 2.0},
      %{id: 3, amount: 3.0},
      %{id: 4, amount: 4.0}
    ]

    right = [
      %{id: 1, amount: 1.0},
      %{id: 2, amount: 2.005},
      %{id: 3, amount: 30.0},
      %{id: 5, amount: 5.0}
    ]

    result =
      TolerantReconciler.reconcile_all(left, right,
        key_fields: [:id],
        rules: [amount: {:numeric, 0.01}]
      )

    assert TolerantReconciler.summary(result) == %{
             identical: 1,
             within_tolerance: 1,
             conflicts: 1,
             only_in_left: 1,
             only_in_right: 1,
             matched: 3
           }
  end

  test "summary of an empty reconciliation is all zeroes" do
    result = TolerantReconciler.reconcile_all([], [], key_fields: [:id])

    assert TolerantReconciler.summary(result) == %{
             identical: 0,
             within_tolerance: 0,
             conflicts: 0,
             only_in_left: 0,
             only_in_right: 0,
             matched: 0
           }
  end
end
