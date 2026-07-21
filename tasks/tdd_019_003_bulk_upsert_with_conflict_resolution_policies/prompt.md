# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule InventoryTest do
  use ExUnit.Case, async: false

  setup do
    case Process.whereis(Inventory) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end

    {:ok, _pid} = Inventory.start_link()
    :ok
  end

  defp seed(sku, name, price, qty) do
    assert {:ok, [{0, :inserted, _}]} =
             Inventory.bulk_upsert([
               %{"sku" => sku, "name" => name, "price" => price, "qty" => qty}
             ])
  end

  test "inserts new items (all-or-nothing)" do
    items = [
      %{"sku" => "A", "name" => "Alpha", "price" => 10, "qty" => 2},
      %{"sku" => "B", "name" => "Beta", "price" => 20}
    ]

    assert {:ok, results} = Inventory.bulk_upsert(items)
    assert {0, :inserted, a} = Enum.at(results, 0)
    assert {1, :inserted, b} = Enum.at(results, 1)
    assert a.qty == 2
    assert b.qty == 0
    assert Inventory.count() == 2
  end

  test "all/0 returns every stored record" do
    assert Inventory.all() == []

    seed("A", "Alpha", 10, 2)
    seed("B", "Beta", 20, 0)

    records = Inventory.all()
    assert length(records) == 2

    by_sku = Map.new(records, fn r -> {r.sku, r} end)
    assert Map.keys(by_sku) |> Enum.sort() == ["A", "B"]
    assert by_sku["A"].name == "Alpha"
    assert by_sku["A"].price == 10
    assert by_sku["A"].qty == 2
    assert by_sku["B"].name == "Beta"
    assert by_sku["B"].qty == 0
  end

  test "all/0 reflects updates and stays deduplicated by sku" do
    seed("A", "Old", 10, 5)

    assert {:ok, [{0, :updated, _}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => "New", "price" => 20, "qty" => 3}],
               on_conflict: :merge
             )

    assert [record] = Inventory.all()
    assert record.sku == "A"
    assert record.name == "New"
    assert record.qty == 8
  end

  test "replace policy overwrites the existing record" do
    seed("A", "Old", 10, 5)

    assert {:ok, [{0, :updated, rec}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => "New", "price" => 20, "qty" => 3}],
               on_conflict: :replace
             )

    assert rec.name == "New"
    assert rec.price == 20
    assert rec.qty == 3
    assert Inventory.get("A").qty == 3
    assert Inventory.count() == 1
  end

  test "merge policy accumulates qty" do
    seed("A", "Old", 10, 5)

    assert {:ok, [{0, :updated, rec}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => "New", "price" => 20, "qty" => 3}],
               on_conflict: :merge
             )

    assert rec.qty == 8
    assert rec.name == "New"
    assert Inventory.get("A").qty == 8
  end

  test "skip policy leaves the existing record untouched" do
    seed("A", "Old", 10, 5)

    assert {:ok, [{0, :skipped, existing}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => "X", "price" => 99, "qty" => 9}],
               on_conflict: :skip
             )

    assert existing.name == "Old"
    assert existing.qty == 5
    assert Inventory.get("A").qty == 5
  end

  test "all-or-nothing rolls back when any item is invalid" do
    items = [
      %{"sku" => "A", "name" => "Alpha", "price" => 10},
      %{"sku" => "B", "price" => 5}
    ]

    assert {:error, results} = Inventory.bulk_upsert(items)
    assert {0, :ok, :valid} = Enum.at(results, 0)
    assert {1, :error, errs} = Enum.at(results, 1)
    assert Map.has_key?(errs, "name")
    assert Inventory.count() == 0
    assert Inventory.all() == []
  end

  test "partial mode applies valid items and reports invalid ones" do
    items = [
      %{"sku" => "A", "name" => "Alpha", "price" => 10},
      %{"sku" => "B", "price" => -5}
    ]

    assert {:ok, results} = Inventory.bulk_upsert(items, partial: true)
    assert {0, :inserted, _} = Enum.at(results, 0)
    assert {1, :error, errs} = Enum.at(results, 1)
    assert Map.has_key?(errs, "price")
    assert Inventory.count() == 1
    assert [%{sku: "A"}] = Inventory.all()
  end

  test "in-batch duplicate sku with merge accumulates across entries" do
    items = [
      %{"sku" => "A", "name" => "First", "price" => 1, "qty" => 2},
      %{"sku" => "A", "name" => "Second", "price" => 2, "qty" => 3}
    ]

    assert {:ok, results} = Inventory.bulk_upsert(items, on_conflict: :merge)
    assert {0, :inserted, first} = Enum.at(results, 0)
    assert {1, :updated, second} = Enum.at(results, 1)
    assert first.qty == 2
    assert second.qty == 5
    assert Inventory.get("A").qty == 5
    assert Inventory.count() == 1
  end

  test "invalid on_conflict policy raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      Inventory.bulk_upsert([], on_conflict: :bogus)
    end
  end

  test "empty batch succeeds" do
    assert {:ok, []} = Inventory.bulk_upsert([])
    assert Inventory.count() == 0
    assert Inventory.all() == []
  end

  # Without opts the conflict policy is :replace: the existing record is
  # overwritten, so qty is the incoming qty (not the accumulated :merge sum)
  # and the incoming name wins (unlike :skip).
  test "omitting on_conflict overwrites an existing sku with the incoming record" do
    seed("A", "Old", 10, 5)

    attrs = %{"sku" => "A", "name" => "New", "price" => 20, "qty" => 3}
    assert {:ok, [{0, :updated, rec}]} = Inventory.bulk_upsert([attrs])

    assert rec.name == "New"
    assert rec.price == 20
    assert rec.qty == 3
    assert Inventory.get("A").name == "New"
    assert Inventory.get("A").price == 20
    assert Inventory.get("A").qty == 3
    assert Inventory.count() == 1
  end

  # Repeating a sku within one batch conflicts against the running state, and
  # under the default policy each repeat replaces rather than accumulating.
  test "omitting on_conflict makes in-batch duplicate skus replace, not accumulate" do
    items = [
      %{"sku" => "A", "name" => "First", "price" => 1, "qty" => 2},
      %{"sku" => "A", "name" => "Second", "price" => 2, "qty" => 3}
    ]

    assert {:ok, results} = Inventory.bulk_upsert(items)
    assert {0, :inserted, first} = Enum.at(results, 0)
    assert {1, :updated, second} = Enum.at(results, 1)
    assert first.qty == 2
    assert second.qty == 3
    assert second.name == "Second"
    assert Inventory.get("A").qty == 3
    assert Inventory.count() == 1
  end

  # "name" must be 1-100 characters, so both an empty name and a 101-character
  # name are validation errors keyed by the string field name.
  test "name outside the 1-100 character range is a validation error" do
    long = String.duplicate("n", 101)

    assert {:error, [{0, :error, long_errs}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => long, "price" => 10}])

    assert Map.has_key?(long_errs, "name")
    assert is_list(long_errs["name"])
    assert Enum.all?(long_errs["name"], &is_binary/1)
    assert Inventory.count() == 0

    assert {:error, [{0, :error, blank_errs}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => "", "price" => 10}])

    assert Map.has_key?(blank_errs, "name")
    assert Inventory.count() == 0
    assert Inventory.all() == []
  end

  test "name of exactly 100 characters is accepted" do
    name = String.duplicate("n", 100)

    assert {:ok, [{0, :inserted, rec}]} =
             Inventory.bulk_upsert([%{"sku" => "A", "name" => name, "price" => 10}])

    assert rec.name == name
    assert Inventory.count() == 1
    assert Inventory.get("A").name == name
  end

  # "qty" is optional but must be a non-negative integer when given; a negative
  # qty fails validation and, in the default mode, blocks the whole batch.
  test "negative qty is a validation error keyed by qty" do
    items = [
      %{"sku" => "A", "name" => "Alpha", "price" => 10, "qty" => 1},
      %{"sku" => "B", "name" => "Beta", "price" => 20, "qty" => -1}
    ]

    assert {:error, results} = Inventory.bulk_upsert(items)
    assert {0, :ok, :valid} = Enum.at(results, 0)
    assert {1, :error, errs} = Enum.at(results, 1)
    assert Map.has_key?(errs, "qty")
    assert is_list(errs["qty"])
    assert Enum.all?(errs["qty"], &is_binary/1)
    assert Inventory.count() == 0
    assert Inventory.all() == []
  end

  test "qty of zero is accepted and non-integer qty is rejected" do
    assert {:ok, [{0, :inserted, rec}]} =
             Inventory.bulk_upsert([
               %{"sku" => "A", "name" => "Alpha", "price" => 10, "qty" => 0}
             ])

    assert rec.qty == 0

    assert {:ok, [{0, :error, errs}]} =
             Inventory.bulk_upsert(
               [%{"sku" => "B", "name" => "Beta", "price" => 10, "qty" => "3"}],
               partial: true
             )

    assert Map.has_key?(errs, "qty")
    assert Inventory.get("B") == nil
    assert Inventory.count() == 1
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
