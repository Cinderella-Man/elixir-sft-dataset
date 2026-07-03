Implement the private `apply_one/3` function. It applies a single already-validated,
normalized record `norm` (with keys `:sku`, `:name`, `:price`, `:qty`) to the backing
`Agent`'s store at zero-based index `i`, honoring the given conflict `policy`, and
returns the per-item result tuple.

Perform the read and write atomically via `Agent.get_and_update(__MODULE__, ...)` so the
lookup and mutation see the same running state (this is what makes repeated skus within a
batch resolve against prior updates). Look up the existing record by `norm.sku` in the
`records` map:

- **No existing record (`nil`):** build `%{sku: norm.sku, name: norm.name, price: norm.price,
  qty: norm.qty}`, store it, and return `{i, :inserted, rec}`.
- **Existing record**, dispatch on `policy`:
  - `:skip` — leave the store untouched and return `{i, :skipped, existing}`.
  - `:replace` — overwrite with a fresh record built from the incoming values (qty = incoming
    qty), store it, and return `{i, :updated, rec}`.
  - `:merge` — keep the existing record's identity but take the incoming `name`/`price` and
    accumulate quantity (`existing.qty + norm.qty`), store it, and return `{i, :updated, rec}`.

In every case the first element of the `get_and_update` return is the result tuple and the
second is the (possibly unchanged) state with its updated `records` map.

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
    # TODO
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