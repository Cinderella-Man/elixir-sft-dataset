# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Inventory do
  @moduledoc """
  Bulk upsert into an in-memory store keyed by `"sku"`, with conflict-resolution
  policies (`:replace`, `:merge`, `:skip`) and index-aware result reporting.

  The store is backed by a named `Agent` registered under this module. Each record
  is a map `%{sku: String.t(), name: String.t(), price: integer, qty: integer}`.
  """

  @type record :: %{sku: String.t(), name: String.t(), price: integer, qty: non_neg_integer}
  @type errors :: %{optional(String.t()) => [String.t()]}
  @type result ::
          {non_neg_integer, :inserted | :updated | :skipped, record}
          | {non_neg_integer, :ok, :valid}
          | {non_neg_integer, :error, errors}

  @policies [:replace, :merge, :skip]

  @doc """
  Start the backing `Agent`, registered under `#{inspect(__MODULE__)}`.
  """
  @spec start_link(keyword) :: Agent.on_start()
  def start_link(_ \\ []) do
    Agent.start_link(fn -> %{records: %{}} end, name: __MODULE__)
  end

  @doc "Return all stored records."
  @spec all() :: [record]
  def all, do: Agent.get(__MODULE__, fn %{records: r} -> Map.values(r) end)

  @doc "Return the number of stored records."
  @spec count() :: non_neg_integer
  def count, do: Agent.get(__MODULE__, fn %{records: r} -> map_size(r) end)

  @doc "Fetch a record by `sku`, or `nil` if absent."
  @spec get(String.t()) :: record | nil
  def get(sku), do: Agent.get(__MODULE__, fn %{records: r} -> Map.get(r, sku) end)

  @doc """
  Bulk upsert. `opts[:on_conflict]` in `#{inspect(@policies)}` (default `:replace`),
  `opts[:partial]` (default `false`).

  Returns `{:ok, results}` on success or `{:error, results}` when validation fails in
  the default all-or-nothing mode. Each result carries the zero-based input index.
  """
  @spec bulk_upsert([map], keyword) :: {:ok, [result]} | {:error, [result]}
  def bulk_upsert(list, opts \\ []) do
    policy = Keyword.get(opts, :on_conflict, :replace)

    unless policy in @policies do
      raise ArgumentError,
            "invalid :on_conflict #{inspect(policy)}, expected one of #{inspect(@policies)}"
    end

    partial? = Keyword.get(opts, :partial, false)

    validations =
      list
      |> Enum.with_index()
      |> Enum.map(fn {attrs, i} -> {i, validate(attrs)} end)

    any_error? = Enum.any?(validations, fn {_, v} -> match?({:error, _}, v) end)

    if not partial? and any_error? do
      results =
        Enum.map(validations, fn
          {i, {:error, errs}} -> {i, :error, errs}
          {i, {:ok, _norm}} -> {i, :ok, :valid}
        end)

      {:error, results}
    else
      results =
        Enum.map(validations, fn
          {i, {:error, errs}} -> {i, :error, errs}
          {i, {:ok, norm}} -> apply_one(i, norm, policy)
        end)

      {:ok, results}
    end
  end

  # -- upsert application ---------------------------------------------------

  defp apply_one(i, norm, policy) do
    Agent.get_and_update(__MODULE__, fn %{records: recs} = st ->
      case Map.get(recs, norm.sku) do
        nil ->
          rec = %{sku: norm.sku, name: norm.name, price: norm.price, qty: norm.qty}
          {{i, :inserted, rec}, %{st | records: Map.put(recs, norm.sku, rec)}}

        existing ->
          case policy do
            :skip ->
              {{i, :skipped, existing}, st}

            :replace ->
              rec = %{sku: norm.sku, name: norm.name, price: norm.price, qty: norm.qty}
              {{i, :updated, rec}, %{st | records: Map.put(recs, norm.sku, rec)}}

            :merge ->
              rec = %{existing | name: norm.name, price: norm.price, qty: existing.qty + norm.qty}
              {{i, :updated, rec}, %{st | records: Map.put(recs, norm.sku, rec)}}
          end
      end
    end)
  end

  # -- validation -----------------------------------------------------------

  defp validate(attrs) do
    errors =
      %{}
      |> put_sku_error(attrs)
      |> put_name_error(attrs)
      |> put_price_error(attrs)
      |> put_qty_error(attrs)

    if map_size(errors) == 0 do
      {:ok,
       %{
         sku: attrs["sku"],
         name: attrs["name"],
         price: attrs["price"],
         qty: normalize_qty(Map.get(attrs, "qty"))
       }}
    else
      {:error, errors}
    end
  end

  defp put_sku_error(errors, attrs) do
    case attrs["sku"] do
      s when is_binary(s) and byte_size(s) > 0 -> errors
      _ -> Map.put(errors, "sku", ["can't be blank"])
    end
  end

  defp put_name_error(errors, attrs) do
    case attrs["name"] do
      n when is_binary(n) and byte_size(n) > 0 ->
        if String.length(n) <= 100,
          do: errors,
          else: Map.put(errors, "name", ["should be at most 100 character(s)"])

      _ ->
        Map.put(errors, "name", ["can't be blank"])
    end
  end

  defp put_price_error(errors, attrs) do
    case attrs["price"] do
      p when is_integer(p) and p > 0 -> errors
      _ -> Map.put(errors, "price", ["must be a positive integer"])
    end
  end

  defp put_qty_error(errors, attrs) do
    case Map.get(attrs, "qty") do
      nil -> errors
      q when is_integer(q) and q >= 0 -> errors
      _ -> Map.put(errors, "qty", ["must be a non-negative integer"])
    end
  end

  defp normalize_qty(nil), do: 0
  defp normalize_qty(q), do: q
end
```

## Test harness — implement the `# TODO` test

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
             Inventory.bulk_upsert([%{"sku" => sku, "name" => name, "price" => price, "qty" => qty}])
  end

  test "inserts new items (all-or-nothing)" do
    # TODO
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
end
```
