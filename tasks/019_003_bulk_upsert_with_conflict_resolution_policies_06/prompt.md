# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `all` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me a self-contained Elixir context module `Inventory` that performs a **bulk upsert** into an in-memory store keyed by a unique `"sku"`, with configurable conflict-resolution policies and per-item, index-aware result reporting.

This is a variation on a create-only bulk endpoint: here each item either **inserts** (new sku) or **updates** (existing sku), and the caller chooses how updates combine with the existing record.

**Store**
- Back the module with a named `Agent` started via `Inventory.start_link/0` (registered under the module name).
- Provide `Inventory.all/0`, `Inventory.count/0`, and `Inventory.get/1` (by sku).
- Each stored record is `%{sku: String.t(), name: String.t(), price: integer, qty: integer}`.

**Input shape**
- Each attribute map: `"sku"` (required, non-empty), `"name"` (required, 1–100 chars), `"price"` (required integer > 0), `"qty"` (optional non-negative integer, default `0`).

**`Inventory.bulk_upsert(list_of_attrs, opts \\ [])`**
- `opts[:on_conflict]` (default `:replace`) selects the update policy; anything other than `:replace | :merge | :skip` raises `ArgumentError`.
  - `:replace` — an existing sku is overwritten with the incoming record (qty = incoming qty).
  - `:merge` — an existing sku keeps its identity; `name`/`price` take the incoming values and `qty` **accumulates** (`existing.qty + incoming.qty`). This makes stock-receiving batches additive.
  - `:skip` — an existing sku is left untouched and reported as skipped.
- Processing is **in order**, so a repeated sku *within the same batch* is treated as a conflict against the running state (e.g., two `:merge` entries for the same sku accumulate).
- `opts[:partial]` (default `false`) selects the failure mode.
- Result tuples carry the zero-based input index: `{index, :inserted, record}`, `{index, :updated, record}`, `{index, :skipped, record}`, or `{index, :error, errors_map}`.
- The accompanying `record` is the record now in the store: for `:inserted` the newly inserted record, for `:updated` the resulting updated record, and for `:skipped` the existing record left in place (not the incoming attrs).
- The `errors_map` is keyed by the offending field's **string** name exactly as it appears in the input attrs, and each value is a list of human-readable message strings — e.g. `%{"name" => ["can't be blank"]}`.
- **Default (all-or-nothing):** if any item fails validation, write nothing and return `{:error, results}` where valid items appear as `{index, :ok, :valid}` and invalid ones as `{index, :error, errors}`. Otherwise apply all items in order and return `{:ok, results}`.
- **`partial: true`:** apply every valid item in order (insert/update/skip per policy and existence), report invalid items as errors, and return `{:ok, results}`.

Use only Elixir/OTP standard library — no external dependencies.

## The module with `all` missing

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

  def all do
    # TODO
  end

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

Give me only the complete implementation of `all` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
