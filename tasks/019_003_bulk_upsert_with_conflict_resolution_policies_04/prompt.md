Implement the private `validate/1` function. It takes a single attribute map
(string-keyed, as received from the caller) and returns either `{:ok, normalized}`
or `{:error, errors}`.

Build an `errors` map by threading an initially empty map through the four
field-checking helpers in order: `put_sku_error/2`, `put_name_error/2`,
`put_price_error/2`, and `put_qty_error/2` (each takes the accumulating errors map
and the raw attrs, adding an entry only when its field is invalid). If the resulting
`errors` map is empty (`map_size == 0`), the attrs are valid: return `{:ok, norm}`
where `norm` is a normalized map with atom keys `sku`, `name`, `price` taken directly
from `attrs["sku"]`, `attrs["name"]`, `attrs["price"]`, and `qty` set to
`normalize_qty(Map.get(attrs, "qty"))` (so a missing `"qty"` becomes `0`). Otherwise
return `{:error, errors}`.

```elixir
defmodule Inventory do
  @moduledoc """
  Bulk upsert into an in-memory store keyed by `"sku"`, with conflict-resolution
  policies (`:replace`, `:merge`, `:skip`) and index-aware result reporting.

  The store is backed by a named `Agent` registered under this module. Each record
  is a map `%{sku: String.t(), name: String.t(), price: integer, qty: integer}`.
  """

  @type record_t :: %{sku: String.t(), name: String.t(), price: integer, qty: non_neg_integer}
  @type errors :: %{optional(String.t()) => [String.t()]}
  @type result ::
          {non_neg_integer, :inserted | :updated | :skipped, record_t}
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
  @spec all() :: [record_t]
  def all, do: Agent.get(__MODULE__, fn %{records: r} -> Map.values(r) end)

  @doc "Return the number of stored records."
  @spec count() :: non_neg_integer
  def count, do: Agent.get(__MODULE__, fn %{records: r} -> map_size(r) end)

  @doc "Fetch a record by `sku`, or `nil` if absent."
  @spec get(String.t()) :: record_t | nil
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
    # TODO
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