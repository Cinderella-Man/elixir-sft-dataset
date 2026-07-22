defmodule LedgerReconcilerTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Count mode (no quantity field)
  # ---------------------------------------------------------------------------

  test "equal row counts per key balance" do
    left = [%{sku: "A"}, %{sku: "A"}, %{sku: "B"}]
    right = [%{sku: "A"}, %{sku: "A"}, %{sku: "B"}]

    result = LedgerReconciler.reconcile(left, right, key_fields: [:sku])

    assert result.discrepancies == []

    a = Enum.find(result.balanced, &(&1.key == %{sku: "A"}))
    assert a.left_total == 2
    assert a.right_total == 2
  end

  test "differing row counts per key produce a discrepancy with delta" do
    left = [%{sku: "A"}, %{sku: "A"}]
    right = [%{sku: "A"}]

    result = LedgerReconciler.reconcile(left, right, key_fields: [:sku])

    assert result.balanced == []
    [d] = result.discrepancies
    assert d.key == %{sku: "A"}
    assert d.left_total == 2
    assert d.right_total == 1
    assert d.delta == 1
  end

  # ---------------------------------------------------------------------------
  # Quantity mode
  # ---------------------------------------------------------------------------

  test "quantities balance even when row counts differ" do
    left = [%{sku: "A", qty: 3}, %{sku: "A", qty: 2}]
    right = [%{sku: "A", qty: 5}]

    result =
      LedgerReconciler.reconcile(left, right, key_fields: [:sku], quantity_field: :qty)

    assert result.discrepancies == []
    [b] = result.balanced
    assert b.left_total == 5
    assert b.right_total == 5
    assert length(b.left) == 2
    assert length(b.right) == 1
  end

  test "quantity discrepancy reports a signed delta" do
    left = [%{sku: "A", qty: 5}]
    right = [%{sku: "A", qty: 8}]

    result =
      LedgerReconciler.reconcile(left, right, key_fields: [:sku], quantity_field: :qty)

    [d] = result.discrepancies
    assert d.left_total == 5
    assert d.right_total == 8
    assert d.delta == -3
  end

  test "a missing quantity field contributes zero" do
    left = [%{sku: "A", qty: 5}, %{sku: "A"}]
    right = [%{sku: "A", qty: 5}]

    result =
      LedgerReconciler.reconcile(left, right, key_fields: [:sku], quantity_field: :qty)

    assert result.discrepancies == []
    [b] = result.balanced
    assert b.left_total == 5
    assert b.right_total == 5
  end

  # ---------------------------------------------------------------------------
  # One-sided keys
  # ---------------------------------------------------------------------------

  test "a key present only on the left is a discrepancy with right total zero" do
    left = [%{sku: "X", qty: 2}]
    right = []

    result =
      LedgerReconciler.reconcile(left, right, key_fields: [:sku], quantity_field: :qty)

    [d] = result.discrepancies
    assert d.left_total == 2
    assert d.right_total == 0
    assert d.delta == 2
    assert d.right == []
  end

  test "a key present only on the right is a discrepancy with left total zero" do
    left = []
    right = [%{sku: "Y"}, %{sku: "Y"}]

    result = LedgerReconciler.reconcile(left, right, key_fields: [:sku])

    [d] = result.discrepancies
    assert d.left_total == 0
    assert d.right_total == 2
    assert d.delta == -2
    assert d.left == []
  end

  # ---------------------------------------------------------------------------
  # Grouping / order preservation
  # ---------------------------------------------------------------------------

  test "grouped records keep their input order" do
    left = [%{sku: "A", n: 1}, %{sku: "A", n: 2}, %{sku: "A", n: 3}]
    right = [%{sku: "A", n: 9}, %{sku: "A", n: 8}, %{sku: "A", n: 7}]

    result = LedgerReconciler.reconcile(left, right, key_fields: [:sku])

    [b] = result.balanced
    assert Enum.map(b.left, & &1.n) == [1, 2, 3]
    assert Enum.map(b.right, & &1.n) == [9, 8, 7]
  end

  # ---------------------------------------------------------------------------
  # Composite keys
  # ---------------------------------------------------------------------------

  test "composite key groups by all key fields" do
    left = [
      %{wh: "east", sku: "A", qty: 4},
      %{wh: "west", sku: "A", qty: 1}
    ]

    right = [
      %{wh: "east", sku: "A", qty: 4},
      %{wh: "west", sku: "A", qty: 9}
    ]

    result =
      LedgerReconciler.reconcile(left, right,
        key_fields: [:wh, :sku],
        quantity_field: :qty
      )

    east = Enum.find(result.balanced, &(&1.key == %{wh: "east", sku: "A"}))
    assert east.left_total == 4

    west = Enum.find(result.discrepancies, &(&1.key == %{wh: "west", sku: "A"}))
    assert west.delta == -8
  end

  # ---------------------------------------------------------------------------
  # Edge cases and errors
  # ---------------------------------------------------------------------------

  test "both lists empty yields empty result" do
    result = LedgerReconciler.reconcile([], [], key_fields: [:sku])
    assert result == %{balanced: [], discrepancies: []}
  end

  test "missing :key_fields raises" do
    assert_raise ArgumentError, fn ->
      LedgerReconciler.reconcile([], [], [])
    end
  end

  # ---------------------------------------------------------------------------
  # Integration
  # ---------------------------------------------------------------------------

  test "mixed inventory reconciliation" do
    left = [
      %{sku: "A", qty: 10},
      %{sku: "B", qty: 5},
      %{sku: "B", qty: 5},
      %{sku: "C", qty: 3}
    ]

    right = [
      %{sku: "A", qty: 10},
      %{sku: "B", qty: 8},
      %{sku: "D", qty: 7}
    ]

    result =
      LedgerReconciler.reconcile(left, right, key_fields: [:sku], quantity_field: :qty)

    balanced_keys = Enum.map(result.balanced, & &1.key.sku) |> Enum.sort()
    assert balanced_keys == ["A"]

    by_sku = Map.new(result.discrepancies, &{&1.key.sku, &1})
    assert by_sku["B"].delta == 2
    assert by_sku["C"].delta == 3
    assert by_sku["D"].delta == -7
  end
end