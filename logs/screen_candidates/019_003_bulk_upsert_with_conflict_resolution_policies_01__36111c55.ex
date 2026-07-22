defmodule Inventory do
  @moduledoc """
  An in-memory inventory context backed by a named `Agent`, keyed by a unique `"sku"`.

  The store holds records shaped as
  `%{sku: String.t(), name: String.t(), price: integer, qty: integer}`.

  The headline operation is `bulk_upsert/2`, which validates a list of attribute maps and
  applies them **in order**, inserting new skus and updating existing ones according to a
  configurable conflict-resolution policy:

    * `:replace` (default) — the existing record is overwritten by the incoming one.
    * `:merge` — `name`/`price` take the incoming values while `qty` accumulates, which makes
      stock-receiving batches additive.
    * `:skip` — the existing record is left untouched and reported as skipped.

  Because processing is sequential against a running state, a sku repeated *within a single
  batch* conflicts with the earlier entry from the same batch (two `:merge` entries for the
  same sku accumulate).

  Failure handling is selected via `opts[:partial]`:

    * `false` (default) — all-or-nothing. If any item is invalid nothing is written and
      `{:error, results}` is returned.
    * `true` — every valid item is applied and invalid items are reported alongside.

  Every result tuple carries the zero-based index of the item in the input list.
  """

  use Agent

  @type record :: %{sku: String.t(), name: String.t(), price: integer, qty: integer}
  @type attrs :: %{optional(String.t()) => term}
  @type errors :: %{optional(String.t()) => [String.t()]}
  @type result ::
          {non_neg_integer, :inserted | :updated | :skipped, record}
          | {non_neg_integer, :ok, :valid}
          | {non_neg_integer, :error, errors}

  @name_max_length 100
  @conflict_policies [:replace, :merge, :skip]

  @doc """
  Starts the inventory store, registered under this module's name, with an empty state.
  """
  @spec start_link() :: Agent.on_start()
  def start_link do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Returns every stored record, sorted by sku for a stable, deterministic ordering.
  """
  @spec all() :: [record]
  def all do
    Agent.get(__MODULE__, fn store -> store |> Map.values() |> Enum.sort_by(& &1.sku) end)
  end

  @doc """
  Returns the number of records currently stored.
  """
  @spec count() :: non_neg_integer
  def count do
    Agent.get(__MODULE__, &map_size/1)
  end

  @doc """
  Fetches the record stored under `sku`, or `nil` when no such record exists.
  """
  @spec get(String.t()) :: record | nil
  def get(sku) do
    Agent.get(__MODULE__, &Map.get(&1, sku))
  end

  @doc """
  Validates and applies a list of attribute maps in order.

  ## Options

    * `:on_conflict` — one of `:replace` (default), `:merge` or `:skip`. Any other value
      raises `ArgumentError`.
    * `:partial` — when `false` (default) a single invalid item aborts the whole batch and
      nothing is written; when `true` all valid items are applied regardless.

  ## Returns

    * `{:ok, results}` — every item was valid (or `partial: true` was given). Results are
      `{index, :inserted | :updated | :skipped, record}` for applied items and
      `{index, :error, errors}` for invalid ones.
    * `{:error, results}` — all-or-nothing mode with at least one invalid item. Nothing was
      written; results are `{index, :ok, :valid}` and `{index, :error, errors}`.

  ## Examples

      iex> Inventory.bulk_upsert([%{"sku" => "a", "name" => "Bolt", "price" => 10}])
      {:ok, [{0, :inserted, %{sku: "a", name: "Bolt", price: 10, qty: 0}}]}

  """
  @spec bulk_upsert([attrs], keyword) :: {:ok, [result]} | {:error, [result]}
  def bulk_upsert(list_of_attrs, opts \\ []) when is_list(list_of_attrs) and is_list(opts) do
    on_conflict = validate_policy!(Keyword.get(opts, :on_conflict, :replace))
    partial? = Keyword.get(opts, :partial, false)

    validated =
      list_of_attrs
      |> Enum.with_index()
      |> Enum.map(fn {attrs, index} -> {index, cast(attrs)} end)

    invalid? = Enum.any?(validated, fn {_index, outcome} -> match?({:error, _}, outcome) end)

    if invalid? and not partial? do
      {:error, Enum.map(validated, &dry_run_result/1)}
    else
      {:ok, apply_batch(validated, on_conflict)}
    end
  end

  # -- validation ------------------------------------------------------------------------

  @spec validate_policy!(term) :: :replace | :merge | :skip
  defp validate_policy!(policy) when policy in @conflict_policies, do: policy

  defp validate_policy!(policy) do
    raise ArgumentError,
          "invalid :on_conflict policy #{inspect(policy)}, " <>
            "expected one of #{inspect(@conflict_policies)}"
  end

  @spec dry_run_result({non_neg_integer, {:ok, record} | {:error, errors}}) :: result
  defp dry_run_result({index, {:ok, _record}}), do: {index, :ok, :valid}
  defp dry_run_result({index, {:error, errors}}), do: {index, :error, errors}

  @spec cast(term) :: {:ok, record} | {:error, errors}
  defp cast(attrs) when is_map(attrs) do
    errors =
      %{}
      |> put_errors("sku", validate_sku(Map.get(attrs, "sku")))
      |> put_errors("name", validate_name(Map.get(attrs, "name")))
      |> put_errors("price", validate_price(Map.get(attrs, "price")))
      |> put_errors("qty", validate_qty(Map.get(attrs, "qty", 0)))

    if map_size(errors) == 0 do
      {:ok,
       %{
         sku: Map.fetch!(attrs, "sku"),
         name: Map.fetch!(attrs, "name"),
         price: Map.fetch!(attrs, "price"),
         qty: Map.get(attrs, "qty", 0)
       }}
    else
      {:error, errors}
    end
  end

  defp cast(_attrs), do: {:error, %{"attrs" => ["must be a map"]}}

  @spec put_errors(errors, String.t(), [String.t()]) :: errors
  defp put_errors(errors, _field, []), do: errors
  defp put_errors(errors, field, messages), do: Map.put(errors, field, messages)

  @spec validate_sku(term) :: [String.t()]
  defp validate_sku(nil), do: ["can't be blank"]
  defp validate_sku(""), do: ["can't be blank"]
  defp validate_sku(sku) when is_binary(sku), do: []
  defp validate_sku(_sku), do: ["must be a string"]

  @spec validate_name(term) :: [String.t()]
  defp validate_name(nil), do: ["can't be blank"]
  defp validate_name(""), do: ["can't be blank"]

  defp validate_name(name) when is_binary(name) do
    if String.length(name) > @name_max_length do
      ["should be at most #{@name_max_length} character(s)"]
    else
      []
    end
  end

  defp validate_name(_name), do: ["must be a string"]

  @spec validate_price(term) :: [String.t()]
  defp validate_price(nil), do: ["can't be blank"]
  defp validate_price(price) when is_integer(price) and price > 0, do: []
  defp validate_price(price) when is_integer(price), do: ["must be greater than 0"]
  defp validate_price(_price), do: ["must be an integer"]

  @spec validate_qty(term) :: [String.t()]
  defp validate_qty(nil), do: ["can't be blank"]
  defp validate_qty(qty) when is_integer(qty) and qty >= 0, do: []
  defp validate_qty(qty) when is_integer(qty), do: ["must be greater than or equal to 0"]
  defp validate_qty(_qty), do: ["must be an integer"]

  # -- application -----------------------------------------------------------------------

  @spec apply_batch([{non_neg_integer, {:ok, record} | {:error, errors}}], atom) :: [result]
  defp apply_batch(validated, on_conflict) do
    Agent.get_and_update(__MODULE__, fn store ->
      {results, new_store} =
        Enum.map_reduce(validated, store, fn entry, acc ->
          apply_entry(entry, acc, on_conflict)
        end)

      {results, new_store}
    end)
  end

  @spec apply_entry({non_neg_integer, {:ok, record} | {:error, errors}}, map, atom) ::
          {result, map}
  defp apply_entry({index, {:error, errors}}, store, _on_conflict) do
    {{index, :error, errors}, store}
  end

  defp apply_entry({index, {:ok, incoming}}, store, on_conflict) do
    case Map.fetch(store, incoming.sku) do
      :error ->
        {{index, :inserted, incoming}, Map.put(store, incoming.sku, incoming)}

      {:ok, existing} ->
        resolve_conflict(index, existing, incoming, store, on_conflict)
    end
  end

  @spec resolve_conflict(non_neg_integer, record, record, map, atom) :: {result, map}
  defp resolve_conflict(index, _existing, incoming, store, :replace) do
    {{index, :updated, incoming}, Map.put(store, incoming.sku, incoming)}
  end

  defp resolve_conflict(index, existing, incoming, store, :merge) do
    merged = %{incoming | qty: existing.qty + incoming.qty}
    {{index, :updated, merged}, Map.put(store, merged.sku, merged)}
  end

  defp resolve_conflict(index, existing, _incoming, store, :skip) do
    {{index, :skipped, existing}, store}
  end
end