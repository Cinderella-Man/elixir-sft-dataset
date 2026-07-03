Implement the public `bulk_upsert/2` function.

It takes a list of attribute maps and an options keyword list (default `[]`), and
performs a bulk upsert against the backing `Agent`.

- Read `opts[:on_conflict]` (default `:replace`). If it is not one of `:replace`,
  `:merge`, or `:skip` (i.e. not in `@policies`), raise `ArgumentError` with a message
  naming the invalid value and the allowed policies.
- Read `opts[:partial]` (default `false`).
- Validate every item with `validate/1`, pairing each with its zero-based index (use
  `Enum.with_index/1`). Keep the `{index, {:ok, norm} | {:error, errs}}` pairs.
- Determine whether any item failed validation.
- Default mode (`partial: false`) **and** at least one failure: write nothing. Build a
  results list where each valid item becomes `{index, :ok, :valid}` and each invalid one
  `{index, :error, errs}`, and return `{:error, results}`.
- Otherwise (no failures, or `partial: true`): process items in order — invalid items
  become `{index, :error, errs}`, valid items are applied via `apply_one/3` with the
  chosen policy — and return `{:ok, results}`.

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
    # TODO
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