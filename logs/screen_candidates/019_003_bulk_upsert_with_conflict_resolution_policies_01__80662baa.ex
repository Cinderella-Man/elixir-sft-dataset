defmodule Inventory do
  @moduledoc """
  An in-memory inventory context backed by a named `Agent`, keyed by a unique `"sku"`.

  The store holds records shaped as
  `%{sku: String.t(), name: String.t(), price: integer, qty: integer}` and is intended to be
  started once per node under the module's own name.

  The centrepiece is `bulk_upsert/2`, which validates a list of raw attribute maps and applies
  them **in input order**. Each item either inserts (new sku) or updates (existing sku); the
  caller picks how updates combine with the existing record via `:on_conflict`:

    * `:replace` (default) — the existing record is overwritten by the incoming one.
    * `:merge` — `name`/`price` take the incoming values while `qty` accumulates, which makes
      stock-receiving batches additive.
    * `:skip` — the existing record is left untouched and the item is reported as skipped.

  Because processing is sequential against a running state, a sku repeated *within the same
  batch* conflicts with the earlier entry from that same batch.

  Failure handling is selected with `:partial`. By default the batch is all-or-nothing: a single
  invalid item means nothing is written. With `partial: true` every valid item is applied and
  invalid ones are merely reported.

  Every result tuple carries the zero-based index of the item in the input list, so callers can
  correlate outcomes with their original payload.
  """

  @typedoc "A stored inventory record."
  @type record :: %{sku: String.t(), name: String.t(), price: integer, qty: integer}

  @typedoc "Validation errors for one item, keyed by field."
  @type errors :: %{optional(atom) => String.t()}

  @typedoc "Conflict-resolution policy for existing skus."
  @type on_conflict :: :replace | :merge | :skip

  @typedoc "A per-item, index-aware result tuple."
  @type result ::
          {non_neg_integer, :inserted, record}
          | {non_neg_integer, :updated, record}
          | {non_neg_integer, :skipped, record}
          | {non_neg_integer, :ok, :valid}
          | {non_neg_integer, :error, errors}

  @name_max_length 100
  @valid_policies [:replace, :merge, :skip]

  @doc """
  Starts the inventory store, registered under `#{inspect(__MODULE__)}`.

  The store begins empty. Returns `{:ok, pid}` or `{:error, {:already_started, pid}}`.
  """
  @spec start_link() :: {:ok, pid} | {:error, term}
  def start_link do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Returns every stored record, sorted by sku for a stable, predictable ordering.
  """
  @spec all() :: [record]
  def all do
    Agent.get(__MODULE__, fn state ->
      state |> Map.values() |> Enum.sort_by(& &1.sku)
    end)
  end

  @doc """
  Returns the number of stored records.
  """
  @spec count() :: non_neg_integer
  def count do
    Agent.get(__MODULE__, &map_size/1)
  end

  @doc """
  Fetches the record for `sku`, or `nil` when no such record exists.
  """
  @spec get(String.t()) :: record | nil
  def get(sku) when is_binary(sku) do
    Agent.get(__MODULE__, &Map.get(&1, sku))
  end

  @doc """
  Validates and applies a batch of attribute maps, in order, against the store.

  ## Options

    * `:on_conflict` — one of `:replace`, `:merge` or `:skip`; defaults to `:replace`. Any other
      value raises `ArgumentError`.
    * `:partial` — when `false` (the default) the batch is all-or-nothing; when `true` valid
      items are applied and invalid ones are only reported.

  ## Return values

  On success returns `{:ok, results}` where each element is `{index, :inserted, record}`,
  `{index, :updated, record}`, `{index, :skipped, record}` or — only in `partial: true` mode —
  `{index, :error, errors}`.

  In all-or-nothing mode, if any item is invalid nothing is written and `{:error, results}` is
  returned, where valid items appear as `{index, :ok, :valid}` and invalid ones as
  `{index, :error, errors}`.

  ## Examples

      iex> Inventory.start_link()
      iex> Inventory.bulk_upsert([%{"sku" => "A", "name" => "Bolt", "price" => 10, "qty" => 2}])
      {:ok, [{0, :inserted, %{sku: "A", name: "Bolt", price: 10, qty: 2}}]}

  """
  @spec bulk_upsert([map], keyword) :: {:ok, [result]} | {:error, [result]}
  def bulk_upsert(list_of_attrs, opts \\ []) when is_list(list_of_attrs) and is_list(opts) do
    policy = validate_policy!(Keyword.get(opts, :on_conflict, :replace))
    partial? = Keyword.get(opts, :partial, false)

    validated = list_of_attrs |> Enum.with_index() |> Enum.map(&validate_indexed/1)

    if partial? do
      {:ok, apply_batch(validated, policy)}
    else
      apply_all_or_nothing(validated, policy)
    end
  end

  # -- conflict policy ------------------------------------------------------------------

  @spec validate_policy!(term) :: on_conflict
  defp validate_policy!(policy) when policy in @valid_policies, do: policy

  defp validate_policy!(other) do
    raise ArgumentError,
          "invalid :on_conflict option #{inspect(other)}, " <>
            "expected one of #{inspect(@valid_policies)}"
  end

  # -- batch application ----------------------------------------------------------------

  @spec apply_all_or_nothing([{non_neg_integer, {:ok, record} | {:error, errors}}], on_conflict) ::
          {:ok, [result]} | {:error, [result]}
  defp apply_all_or_nothing(validated, policy) do
    if Enum.any?(validated, &match?({_index, {:error, _errors}}, &1)) do
      {:error, Enum.map(validated, &dry_run_result/1)}
    else
      {:ok, apply_batch(validated, policy)}
    end
  end

  @spec dry_run_result({non_neg_integer, {:ok, record} | {:error, errors}}) :: result
  defp dry_run_result({index, {:ok, _record}}), do: {index, :ok, :valid}
  defp dry_run_result({index, {:error, errors}}), do: {index, :error, errors}

  # Applies the valid items sequentially inside a single Agent transaction so that the running
  # state (and therefore intra-batch sku conflicts) is observed in input order.
  @spec apply_batch([{non_neg_integer, {:ok, record} | {:error, errors}}], on_conflict) ::
          [result]
  defp apply_batch(validated, policy) do
    Agent.get_and_update(__MODULE__, fn state ->
      {results, new_state} =
        Enum.reduce(validated, {[], state}, fn item, {acc, current} ->
          {result, next} = apply_item(item, policy, current)
          {[result | acc], next}
        end)

      {Enum.reverse(results), new_state}
    end)
  end

  @spec apply_item(
          {non_neg_integer, {:ok, record} | {:error, errors}},
          on_conflict,
          %{optional(String.t()) => record}
        ) :: {result, %{optional(String.t()) => record}}
  defp apply_item({index, {:error, errors}}, _policy, state) do
    {{index, :error, errors}, state}
  end

  defp apply_item({index, {:ok, incoming}}, policy, state) do
    case Map.fetch(state, incoming.sku) do
      :error ->
        {{index, :inserted, incoming}, Map.put(state, incoming.sku, incoming)}

      {:ok, existing} ->
        resolve_conflict(index, existing, incoming, policy, state)
    end
  end

  @spec resolve_conflict(
          non_neg_integer,
          record,
          record,
          on_conflict,
          %{optional(String.t()) => record}
        ) :: {result, %{optional(String.t()) => record}}
  defp resolve_conflict(index, _existing, incoming, :replace, state) do
    {{index, :updated, incoming}, Map.put(state, incoming.sku, incoming)}
  end

  defp resolve_conflict(index, existing, incoming, :merge, state) do
    merged = %{existing | name: incoming.name, price: incoming.price, qty: existing.qty + incoming.qty}

    {{index, :updated, merged}, Map.put(state, merged.sku, merged)}
  end

  defp resolve_conflict(index, existing, _incoming, :skip, state) do
    {{index, :skipped, existing}, state}
  end

  # -- validation -----------------------------------------------------------------------

  @spec validate_indexed({map, non_neg_integer}) ::
          {non_neg_integer, {:ok, record} | {:error, errors}}
  defp validate_indexed({attrs, index}), do: {index, validate(attrs)}

  @spec validate(term) :: {:ok, record} | {:error, errors}
  defp validate(attrs) when is_map(attrs) do
    errors =
      %{}
      |> put_error(:sku, validate_sku(Map.get(attrs, "sku")))
      |> put_error(:name, validate_name(Map.get(attrs, "name")))
      |> put_error(:price, validate_price(Map.get(attrs, "price")))
      |> put_error(:qty, validate_qty(Map.get(attrs, "qty", 0)))

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

  defp validate(_attrs), do: {:error, %{base: "must be a map of attributes"}}

  @spec put_error(errors, atom, :ok | {:error, String.t()}) :: errors
  defp put_error(errors, _field, :ok), do: errors
  defp put_error(errors, field, {:error, message}), do: Map.put(errors, field, message)

  @spec validate_sku(term) :: :ok | {:error, String.t()}
  defp validate_sku(nil), do: {:error, "is required"}
  defp validate_sku(sku) when is_binary(sku) and byte_size(sku) > 0, do: :ok
  defp validate_sku(sku) when is_binary(sku), do: {:error, "must not be empty"}
  defp validate_sku(_sku), do: {:error, "must be a string"}

  @spec validate_name(term) :: :ok | {:error, String.t()}
  defp validate_name(nil), do: {:error, "is required"}

  defp validate_name(name) when is_binary(name) do
    case String.length(name) do
      0 -> {:error, "must not be empty"}
      length when length > @name_max_length -> {:error, "must be at most 100 characters"}
      _length -> :ok
    end
  end

  defp validate_name(_name), do: {:error, "must be a string"}

  @spec validate_price(term) :: :ok | {:error, String.t()}
  defp validate_price(nil), do: {:error, "is required"}
  defp validate_price(price) when is_integer(price) and price > 0, do: :ok
  defp validate_price(price) when is_integer(price), do: {:error, "must be greater than 0"}
  defp validate_price(_price), do: {:error, "must be an integer"}

  @spec validate_qty(term) :: :ok | {:error, String.t()}
  defp validate_qty(qty) when is_integer(qty) and qty >= 0, do: :ok
  defp validate_qty(qty) when is_integer(qty), do: {:error, "must be greater than or equal to 0"}
  defp validate_qty(_qty), do: {:error, "must be an integer"}
end