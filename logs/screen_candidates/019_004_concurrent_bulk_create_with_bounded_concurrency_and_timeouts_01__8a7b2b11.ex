defmodule ConcurrentCatalog do
  @moduledoc """
  An in-memory item catalog supporting concurrent bulk creation with a bounded
  concurrency pool, per-item timeouts, and index-aware, order-preserving results.

  The store is backed by a named `Agent` (registered under this module's name) which
  serializes all writes, so it stays consistent under concurrent access. Each stored
  item is a map of the shape `%{id: integer, name: String.t(), price: integer}`.

  `bulk_create/2` runs each item's validation and insert inside its own task via
  `Task.async_stream/3` with `ordered: true` and `on_timeout: :kill_task`. Every item is
  independent, so the operation is always partial: one result is returned per input item,
  in the original input order, tagged with its zero-based index.

  Two optional test hooks simulate real work: `"delay"` (milliseconds the insert sleeps)
  and `"fail"` (truthy value making the insert fail). The `peak/0` high-water mark records
  the maximum number of item tasks that were ever running simultaneously, which makes the
  `:max_concurrency` bound observable from tests.
  """

  @default_max_concurrency 4
  @default_timeout_ms 1_000
  @name_max_length 100

  @type attrs :: %{optional(String.t()) => term()}
  @type item :: %{id: pos_integer(), name: String.t(), price: pos_integer()}
  @type errors :: %{optional(String.t()) => [String.t()]}
  @type reason :: {:validation, errors()} | :insert_failed | :timeout
  @type result :: {non_neg_integer(), :ok, item()} | {non_neg_integer(), :error, reason()}

  @doc """
  Starts the catalog `Agent` registered under `ConcurrentCatalog`.

  The initial state holds an empty item map, the next id to assign, and the running/peak
  task counters used to observe the concurrency bound.
  """
  @spec start_link() :: {:ok, pid()} | {:error, term()}
  def start_link do
    Agent.start_link(fn -> %{items: %{}, next_id: 1, running: 0, peak: 0} end, name: __MODULE__)
  end

  @doc """
  Returns all stored items, sorted by ascending id.
  """
  @spec all() :: [item()]
  def all do
    __MODULE__
    |> Agent.get(fn state -> Map.values(state.items) end)
    |> Enum.sort_by(& &1.id)
  end

  @doc """
  Returns the number of stored items.
  """
  @spec count() :: non_neg_integer()
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.items) end)
  end

  @doc """
  Returns the item stored under `id`, or `nil` when no such item exists.
  """
  @spec get(term()) :: item() | nil
  def get(id) do
    Agent.get(__MODULE__, fn state -> Map.get(state.items, id) end)
  end

  @doc """
  Returns the high-water mark of simultaneously running item tasks.

  Useful for asserting that `bulk_create/2` never exceeds its `:max_concurrency` bound.
  """
  @spec peak() :: non_neg_integer()
  def peak do
    Agent.get(__MODULE__, fn state -> state.peak end)
  end

  @doc """
  Concurrently validates and inserts each map in `list_of_attrs`.

  Options:

    * `:max_concurrency` — maximum number of item tasks running at once (default `4`).
    * `:timeout_ms` — per-item time budget in milliseconds (default `1000`); an item that
      exceeds it is killed and reported as `:timeout`.

  Returns a plain list with exactly one result per input item, in the original input order.
  Each result is `{index, :ok, item}` or `{index, :error, reason}`, where `index` is the
  zero-based position in the input and `reason` is one of `{:validation, errors_map}`,
  `:insert_failed`, or `:timeout`.

  ## Examples

      iex> ConcurrentCatalog.bulk_create([%{"name" => "Ada", "price" => 0}])
      [{0, :error, {:validation, %{"price" => ["must be a positive integer"]}}}]

  """
  @spec bulk_create([attrs()], keyword()) :: [result()]
  def bulk_create(list_of_attrs, opts \\ []) when is_list(list_of_attrs) and is_list(opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    list_of_attrs
    |> Enum.with_index()
    |> Task.async_stream(
      fn {attrs, index} -> {index, process_item(attrs)} end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.with_index()
    |> Enum.map(&to_result/1)
  end

  # -- internals ------------------------------------------------------------------

  @spec to_result({{:ok, {non_neg_integer(), {:ok, item()} | {:error, reason()}}}, integer()}) ::
          result()
  defp to_result({{:ok, {index, {:ok, item}}}, _stream_index}), do: {index, :ok, item}
  defp to_result({{:ok, {index, {:error, reason}}}, _stream_index}), do: {index, :error, reason}
  defp to_result({{:exit, :timeout}, stream_index}), do: {stream_index, :error, :timeout}
  defp to_result({{:exit, _reason}, stream_index}), do: {stream_index, :error, :insert_failed}

  @spec process_item(term()) :: {:ok, item()} | {:error, reason()}
  defp process_item(attrs) do
    with {:ok, valid} <- validate(attrs) do
      track(fn -> insert(valid, attrs) end)
    end
  end

  # Bumps the running counter (updating the peak high-water mark), runs `fun`, then
  # decrements. The counters live in the Agent, which serializes the updates.
  @spec track((-> result_or_error)) :: result_or_error when result_or_error: var
  defp track(fun) do
    Agent.update(__MODULE__, fn state ->
      running = state.running + 1
      %{state | running: running, peak: max(state.peak, running)}
    end)

    try do
      fun.()
    after
      Agent.update(__MODULE__, fn state -> %{state | running: max(state.running - 1, 0)} end)
    end
  end

  @spec insert(%{name: String.t(), price: pos_integer()}, map()) ::
          {:ok, item()} | {:error, :insert_failed}
  defp insert(valid, attrs) do
    case Map.get(attrs, "delay") do
      delay when is_integer(delay) and delay > 0 -> Process.sleep(delay)
      _other -> :ok
    end

    if truthy?(Map.get(attrs, "fail")) do
      {:error, :insert_failed}
    else
      item =
        Agent.get_and_update(__MODULE__, fn state ->
          item = %{id: state.next_id, name: valid.name, price: valid.price}
          {item, %{state | items: Map.put(state.items, item.id, item), next_id: item.id + 1}}
        end)

      {:ok, item}
    end
  end

  @spec truthy?(term()) :: boolean()
  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(_other), do: true

  @spec validate(term()) :: {:ok, %{name: String.t(), price: pos_integer()}} | {:error, reason()}
  defp validate(attrs) when is_map(attrs) do
    errors =
      %{}
      |> put_errors("name", validate_name(Map.get(attrs, "name")))
      |> put_errors("price", validate_price(Map.get(attrs, "price")))

    if map_size(errors) == 0 do
      {:ok, %{name: Map.fetch!(attrs, "name"), price: Map.fetch!(attrs, "price")}}
    else
      {:error, {:validation, errors}}
    end
  end

  defp validate(_attrs), do: {:error, {:validation, %{"name" => ["is required"]}}}

  @spec put_errors(errors(), String.t(), [String.t()]) :: errors()
  defp put_errors(errors, _field, []), do: errors
  defp put_errors(errors, field, messages), do: Map.put(errors, field, messages)

  @spec validate_name(term()) :: [String.t()]
  defp validate_name(nil), do: ["is required"]

  defp validate_name(name) when is_binary(name) do
    length = String.length(name)

    if length >= 1 and length <= @name_max_length do
      []
    else
      ["must be between 1 and #{@name_max_length} characters"]
    end
  end

  defp validate_name(_name), do: ["must be a string"]

  @spec validate_price(term()) :: [String.t()]
  defp validate_price(nil), do: ["is required"]
  defp validate_price(price) when is_integer(price) and price > 0, do: []
  defp validate_price(_price), do: ["must be a positive integer"]
end