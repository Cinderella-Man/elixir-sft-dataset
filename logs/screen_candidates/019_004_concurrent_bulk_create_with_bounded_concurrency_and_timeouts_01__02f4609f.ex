defmodule ConcurrentCatalog do
  @moduledoc """
  An in-memory catalog context that supports **concurrent bulk creation** of items with a
  bounded concurrency pool, per-item timeouts, and index-aware, order-preserving results.

  The store is a named `Agent` (registered under this module's name) holding:

    * `:items` — a map of `id => item`, where an item is
      `%{id: integer, name: String.t(), price: integer}`;
    * `:next_id` — the monotonically increasing id counter;
    * `:running` — the number of item tasks currently executing;
    * `:peak` — the high-water mark of `:running`, exposed via `peak/0` so tests can verify
      that the concurrency bound was respected.

  ## Input shape

  Each attribute map is a string-keyed map:

    * `"name"` — required, a string of 1..100 characters;
    * `"price"` — required, an integer greater than zero;
    * `"delay"` — optional test hook, integer milliseconds the insert takes;
    * `"fail"` — optional test hook, truthy means the insert fails.

  ## Results

  `bulk_create/2` returns a plain list (no `{:ok, _}` / `{:error, _}` wrapper) with exactly one
  entry per input, in the original input order. Each entry is `{index, :ok, item}` or
  `{index, :error, reason}` where `reason` is `{:validation, errors_map}`, `:insert_failed`, or
  `:timeout`. Every item is independent, so a bulk run is always partial: successes persist even
  when siblings fail or time out.

  Timed-out and failed items are never inserted, and the `Agent` serializes all writes so the
  store stays consistent under concurrent access.
  """

  @default_max_concurrency 4
  @default_timeout_ms 1_000
  @name_max_length 100

  @type item :: %{id: pos_integer(), name: String.t(), price: pos_integer()}
  @type attrs :: %{optional(String.t()) => term()}
  @type reason :: {:validation, %{optional(atom()) => [String.t()]}} | :insert_failed | :timeout
  @type result :: {non_neg_integer(), :ok, item()} | {non_neg_integer(), :error, reason()}

  @doc """
  Starts the catalog `Agent` registered under this module's name.

  Returns `{:ok, pid}` on success or `{:error, {:already_started, pid}}` if it is already running.
  """
  @spec start_link() :: {:ok, pid()} | {:error, term()}
  def start_link do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  @doc """
  Returns every stored item, sorted by ascending id.
  """
  @spec all() :: [item()]
  def all do
    Agent.get(__MODULE__, fn state ->
      state.items |> Map.values() |> Enum.sort_by(& &1.id)
    end)
  end

  @doc """
  Returns the number of stored items.
  """
  @spec count() :: non_neg_integer()
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.items) end)
  end

  @doc """
  Fetches a single item by `id`, returning `{:ok, item}` or `:error` when absent.
  """
  @spec get(term()) :: {:ok, item()} | :error
  def get(id) do
    Agent.get(__MODULE__, fn state -> Map.fetch(state.items, id) end)
  end

  @doc """
  Returns the high-water mark of simultaneously-running item tasks observed so far.

  This never exceeds the `:max_concurrency` used by `bulk_create/2` and is intended for
  verifying the concurrency bound in tests.
  """
  @spec peak() :: non_neg_integer()
  def peak do
    Agent.get(__MODULE__, fn state -> state.peak end)
  end

  @doc """
  Concurrently validates and inserts each attribute map in `list_of_attrs`.

  ## Options

    * `:max_concurrency` — at most this many item tasks run at once (default `#{@default_max_concurrency}`);
    * `:timeout_ms` — per-item time budget in milliseconds; an item exceeding it is killed and
      reported as `{index, :error, :timeout}` (default `#{@default_timeout_ms}`).

  Returns a list of `{index, :ok, item}` / `{index, :error, reason}` tuples in the original input
  order, one per input element.
  """
  @spec bulk_create([attrs()], keyword()) :: [result()]
  def bulk_create(list_of_attrs, opts \\ []) when is_list(list_of_attrs) and is_list(opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    list_of_attrs
    |> Enum.with_index()
    |> Task.async_stream(
      fn {attrs, index} -> process_item(attrs, index) end,
      max_concurrency: max_concurrency,
      timeout: timeout_ms,
      ordered: true,
      on_timeout: :kill_task
    )
    |> Enum.with_index()
    |> Enum.map(&normalize_result/1)
  end

  # -- Internals -------------------------------------------------------------------------------

  @spec initial_state() :: %{items: %{optional(pos_integer()) => item()}, next_id: pos_integer(),
          running: non_neg_integer(), peak: non_neg_integer()}
  defp initial_state do
    %{items: %{}, next_id: 1, running: 0, peak: 0}
  end

  @spec normalize_result({{:ok, result()} | {:exit, term()}, non_neg_integer()}) :: result()
  defp normalize_result({{:ok, result}, _index}), do: result
  defp normalize_result({{:exit, :timeout}, index}), do: {index, :error, :timeout}
  defp normalize_result({{:exit, _other}, index}), do: {index, :error, :insert_failed}

  @spec process_item(attrs(), non_neg_integer()) :: result()
  defp process_item(attrs, index) do
    with {:ok, params} <- validate(attrs) do
      insert(params, index)
    else
      {:error, errors} -> {index, :error, {:validation, errors}}
    end
  end

  # The counter is decremented in an `after` block so a killed task cannot leak a phantom
  # running-task count; the task is killed while sleeping, so this only runs on normal exits.
  @spec insert(map(), non_neg_integer()) :: result()
  defp insert(params, index) do
    enter_task()

    try do
      simulate_work(params.delay)

      if params.fail do
        {index, :error, :insert_failed}
      else
        {index, :ok, do_insert(params)}
      end
    after
      leave_task()
    end
  end

  @spec simulate_work(non_neg_integer()) :: :ok
  defp simulate_work(0), do: :ok
  defp simulate_work(delay) when delay > 0, do: Process.sleep(delay)

  @spec do_insert(map()) :: item()
  defp do_insert(params) do
    Agent.get_and_update(__MODULE__, fn state ->
      item = %{id: state.next_id, name: params.name, price: params.price}
      {item, %{state | items: Map.put(state.items, item.id, item), next_id: state.next_id + 1}}
    end)
  end

  @spec enter_task() :: :ok
  defp enter_task do
    Agent.update(__MODULE__, fn state ->
      running = state.running + 1
      %{state | running: running, peak: max(state.peak, running)}
    end)
  end

  @spec leave_task() :: :ok
  defp leave_task do
    Agent.update(__MODULE__, fn state -> %{state | running: max(state.running - 1, 0)} end)
  end

  @spec validate(term()) :: {:ok, map()} | {:error, %{optional(atom()) => [String.t()]}}
  defp validate(attrs) when is_map(attrs) do
    errors =
      %{}
      |> validate_name(Map.get(attrs, "name"))
      |> validate_price(Map.get(attrs, "price"))
      |> validate_delay(Map.get(attrs, "delay"))

    if errors == %{} do
      {:ok,
       %{
         name: Map.get(attrs, "name"),
         price: Map.get(attrs, "price"),
         delay: Map.get(attrs, "delay", 0) || 0,
         fail: truthy?(Map.get(attrs, "fail"))
       }}
    else
      {:error, errors}
    end
  end

  defp validate(_attrs), do: {:error, %{base: ["must be a map of attributes"]}}

  @spec validate_name(map(), term()) :: map()
  defp validate_name(errors, nil), do: add_error(errors, :name, "can't be blank")

  defp validate_name(errors, name) when is_binary(name) do
    length = String.length(name)

    cond do
      length < 1 -> add_error(errors, :name, "can't be blank")
      length > @name_max_length -> add_error(errors, :name, "should be at most 100 character(s)")
      true -> errors
    end
  end

  defp validate_name(errors, _name), do: add_error(errors, :name, "is invalid")

  @spec validate_price(map(), term()) :: map()
  defp validate_price(errors, nil), do: add_error(errors, :price, "can't be blank")

  defp validate_price(errors, price) when is_integer(price) do
    if price > 0, do: errors, else: add_error(errors, :price, "must be greater than 0")
  end

  defp validate_price(errors, _price), do: add_error(errors, :price, "is invalid")

  @spec validate_delay(map(), term()) :: map()
  defp validate_delay(errors, nil), do: errors

  defp validate_delay(errors, delay) when is_integer(delay) do
    if delay >= 0, do: errors, else: add_error(errors, :delay, "must be greater than or equal to 0")
  end

  defp validate_delay(errors, _delay), do: add_error(errors, :delay, "is invalid")

  @spec add_error(map(), atom(), String.t()) :: map()
  defp add_error(errors, field, message) do
    Map.update(errors, field, [message], fn messages -> messages ++ [message] end)
  end

  @spec truthy?(term()) :: boolean()
  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(_value), do: true
end