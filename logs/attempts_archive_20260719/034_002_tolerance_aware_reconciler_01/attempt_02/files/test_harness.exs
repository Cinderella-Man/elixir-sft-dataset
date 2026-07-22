defmodule ReconcilerToleranceTest do
  use ExUnit.Case, async: false

  test "default comparison is exact value equality" do
    left = [%{id: 1, price: 10.0}]
    right = [%{id: 1, price: 10.5}]
    result = Reconciler.reconcile(left, right, key_fields: [:id])
    [entry] = result.matched
    assert entry.differences == %{price: %{left: 10.0, right: 10.5}}
  end

  test "numeric tolerance treats near-equal values as equal" do
    left = [%{id: 1, price: 10.0}]
    right = [%{id: 1, price: 10.4}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{price: {:tolerance, 0.5}}
      )

    [entry] = result.matched
    assert entry.differences == %{}
  end

  test "numeric tolerance still reports values beyond the tolerance" do
    left = [%{id: 1, price: 10.0}]
    right = [%{id: 1, price: 11.0}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{price: {:tolerance, 0.5}}
      )

    [entry] = result.matched
    assert entry.differences == %{price: %{left: 10.0, right: 11.0}}
  end

  test "case-insensitive comparator ignores casing" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "alice"}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{name: :case_insensitive}
      )

    assert hd(result.matched).differences == %{}
  end

  test "case-insensitive comparator still detects real differences" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "Bob"}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{name: :case_insensitive}
      )

    assert hd(result.matched).differences == %{name: %{left: "Alice", right: "Bob"}}
  end

  test "custom 2-arity predicate defines equality" do
    same_abs = fn l, r -> abs(l) == abs(r) end
    left = [%{id: 1, delta: -5}]
    right = [%{id: 1, delta: 5}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{delta: same_abs}
      )

    assert hd(result.matched).differences == %{}
  end

  test "comparators only affect their own fields" do
    left = [%{id: 1, price: 10.0, name: "Alice"}]
    right = [%{id: 1, price: 10.2, name: "Bob"}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{price: {:tolerance, 0.5}}
      )

    # price within tolerance -> equal; name uses default exact -> differs
    assert hd(result.matched).differences == %{name: %{left: "Alice", right: "Bob"}}
  end

  test "tolerance rule falls back to exact when values are not numbers" do
    left = [%{id: 1, price: nil}]
    right = [%{id: 1, price: 10.0}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{price: {:tolerance, 0.5}}
      )

    assert hd(result.matched).differences == %{price: %{left: nil, right: 10.0}}
  end

  test "missing field treated as nil under case-insensitive rule" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{name: :case_insensitive}
      )

    assert hd(result.matched).differences == %{name: %{left: "Alice", right: nil}}
  end

  test "identical records with comparators still produce empty diff" do
    left = [%{id: 1, name: "Alice", price: 10.0}]
    right = [%{id: 1, name: "ALICE", price: 10.1}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{name: :case_insensitive, price: {:tolerance, 0.2}}
      )

    assert hd(result.matched).differences == %{}
  end

  test "compare_fields still restricts which fields are diffed" do
    left = [%{id: 1, name: "Alice", ref: "old"}]
    right = [%{id: 1, name: "alice", ref: "new"}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        compare_fields: [:name],
        comparators: %{name: :case_insensitive}
      )

    assert hd(result.matched).differences == %{}
  end

  test "composite keys still match exactly" do
    left = [%{org: 1, uid: 10, v: 1.0}, %{org: 1, uid: 20, v: 2.0}]
    right = [%{org: 1, uid: 10, v: 1.1}, %{org: 2, uid: 10, v: 9.0}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:org, :uid],
        comparators: %{v: {:tolerance, 0.2}}
      )

    assert length(result.matched) == 1
    assert hd(result.matched).differences == %{}
    assert length(result.only_in_left) == 1
    assert length(result.only_in_right) == 1
  end

  test "empty inputs yield empty buckets" do
    assert Reconciler.reconcile([], [], key_fields: [:id]) ==
             %{matched: [], only_in_left: [], only_in_right: []}
  end

  test "raises when key_fields missing" do
    assert_raise ArgumentError, fn ->
      Reconciler.reconcile([%{id: 1}], [%{id: 1}], [])
    end
  end
end