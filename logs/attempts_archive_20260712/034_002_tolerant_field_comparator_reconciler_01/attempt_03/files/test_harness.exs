defmodule ReconcilerTest do
  use ExUnit.Case, async: false

  defp matched_for(result, id) do
    Enum.find(result.matched, fn e -> e.left.id == id end)
  end

  # ---------------------------------------------------------------------------
  # Basic matching (exact keys)
  # ---------------------------------------------------------------------------

  test "records present in both lists appear in :matched" do
    left = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    right = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert length(result.matched) == 2
    assert result.only_in_left == []
    assert result.only_in_right == []
  end

  test "records only in one side are reported" do
    left = [%{id: 1}, %{id: 2}]
    right = [%{id: 1}, %{id: 3}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])

    assert result.only_in_left == [%{id: 2}]
    assert result.only_in_right == [%{id: 3}]
    assert length(result.matched) == 1
  end

  test "both empty lists yield empty result" do
    assert Reconciler.reconcile([], [], key_fields: [:id]) ==
             %{matched: [], only_in_left: [], only_in_right: []}
  end

  # ---------------------------------------------------------------------------
  # Default exact comparison
  # ---------------------------------------------------------------------------

  test "identical matched records have empty differences map" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alice", age: 30}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])
    [entry] = result.matched
    assert entry.differences == %{}
  end

  test "differing fields default to == comparison" do
    left = [%{id: 1, name: "Alice", age: 30}]
    right = [%{id: 1, name: "Alicia", age: 31}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])
    [entry] = result.matched

    assert entry.differences == %{
             name: %{left: "Alice", right: "Alicia"},
             age: %{left: 30, right: 31}
           }
  end

  test "matched entry carries full original records" do
    left = [%{id: 1, name: "Alice", role: "admin"}]
    right = [%{id: 1, name: "Alice", role: "user"}]

    result = Reconciler.reconcile(left, right, key_fields: [:id])
    [entry] = result.matched
    assert entry.left == %{id: 1, name: "Alice", role: "admin"}
    assert entry.right == %{id: 1, name: "Alice", role: "user"}
  end

  # ---------------------------------------------------------------------------
  # :numeric comparator with tolerance
  # ---------------------------------------------------------------------------

  test "numeric comparator treats values within tolerance as equal" do
    left = [%{id: 1, temp: 30.0}]
    right = [%{id: 1, temp: 30.4}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{temp: {:numeric, 0.5}}
      )

    [entry] = result.matched
    assert entry.differences == %{}
  end

  test "numeric comparator reports original values when outside tolerance" do
    left = [%{id: 1, temp: 30.0}]
    right = [%{id: 1, temp: 31.0}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{temp: {:numeric, 0.5}}
      )

    [entry] = result.matched
    assert entry.differences == %{temp: %{left: 30.0, right: 31.0}}
  end

  test "numeric comparator falls back to == when a value is not a number" do
    left = [%{id: 1, temp: 30.0}]
    # :temp missing on the right, so it is treated as nil
    right = [%{id: 1}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{temp: {:numeric, 100.0}}
      )

    [entry] = result.matched
    assert entry.differences == %{temp: %{left: 30.0, right: nil}}
  end

  # ---------------------------------------------------------------------------
  # :case_insensitive comparator
  # ---------------------------------------------------------------------------

  test "case_insensitive comparator ignores letter case" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "alice"}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{name: :case_insensitive}
      )

    [entry] = result.matched
    assert entry.differences == %{}
  end

  test "case_insensitive comparator still reports genuine differences" do
    left = [%{id: 1, name: "Alice"}]
    right = [%{id: 1, name: "Bob"}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{name: :case_insensitive}
      )

    [entry] = result.matched
    assert entry.differences == %{name: %{left: "Alice", right: "Bob"}}
  end

  # ---------------------------------------------------------------------------
  # custom function comparator
  # ---------------------------------------------------------------------------

  test "custom 2-arity comparator decides equality" do
    left = [%{id: 1, price: 9.6}]
    right = [%{id: 1, price: 10.2}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{price: fn l, r -> round(l) == round(r) end}
      )

    [entry] = result.matched
    # round(9.6) == round(10.2) == 10, so considered equal
    assert entry.differences == %{}
  end

  test "custom comparator reporting a difference carries original values" do
    left = [%{id: 1, price: 9.6}]
    right = [%{id: 1, price: 8.2}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{price: fn l, r -> round(l) == round(r) end}
      )

    [entry] = result.matched
    assert entry.differences == %{price: %{left: 9.6, right: 8.2}}
  end

  # ---------------------------------------------------------------------------
  # compare_fields still restricts the field set
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
    assert entry.differences == %{}
  end

  test "fields without a comparator use == even when others use comparators" do
    left = [%{id: 1, name: "Alice", temp: 30.0}]
    right = [%{id: 1, name: "Alicia", temp: 30.1}]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{temp: {:numeric, 1.0}}
      )

    [entry] = result.matched
    # temp within tolerance -> equal; name compared with == -> differs
    assert entry.differences == %{name: %{left: "Alice", right: "Alicia"}}
  end

  # ---------------------------------------------------------------------------
  # composite keys
  # ---------------------------------------------------------------------------

  test "composite key matches only when all key fields are equal" do
    left = [
      %{org_id: 1, user_id: 10, name: "Alice"},
      %{org_id: 1, user_id: 20, name: "Bob"}
    ]

    right = [
      %{org_id: 1, user_id: 10, name: "alice"},
      %{org_id: 2, user_id: 10, name: "Charlie"}
    ]

    result =
      Reconciler.reconcile(left, right,
        key_fields: [:org_id, :user_id],
        comparators: %{name: :case_insensitive}
      )

    assert length(result.matched) == 1
    assert length(result.only_in_left) == 1
    assert length(result.only_in_right) == 1

    [entry] = result.matched
    assert entry.differences == %{}
  end

  # ---------------------------------------------------------------------------
  # integration
  # ---------------------------------------------------------------------------

  test "mixed scenario with comparators, diffs, and uniques" do
    left = [
      %{id: 1, name: "Alice", temp: 20.0},
      %{id: 2, name: "Bob", temp: 25.0},
      %{id: 3, name: "Charlie", temp: 30.0}
    ]

    right = [
      %{id: 1, name: "ALICE", temp: 20.2},
      %{id: 2, name: "Bob", temp: 40.0},
      %{id: 4, name: "Diana", temp: 10.0}
    ]

    comparators = %{name: :case_insensitive, temp: {:numeric, 0.5}}

    result =
      Reconciler.reconcile(left, right, key_fields: [:id], comparators: comparators)

    assert length(result.matched) == 2
    assert hd(result.only_in_left).id == 3
    assert hd(result.only_in_right).id == 4

    one = matched_for(result, 1)
    assert one.differences == %{}

    two = matched_for(result, 2)
    assert two.differences == %{temp: %{left: 25.0, right: 40.0}}
  end
end
