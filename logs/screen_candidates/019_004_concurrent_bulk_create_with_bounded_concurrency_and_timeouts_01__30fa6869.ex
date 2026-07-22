defmodule ConcurrentCatalog do
  @moduledoc """
  An in-memory catalog context that performs bounded-concurrency bulk creation of items.

  The store is backed by a named `Agent` (registered under this module's name) which holds
  the inserted items, the next id to assign, and bookkeeping for the high-water mark of
  simultaneously-running item tasks.

  `bulk_create/2` validates and inserts each item concurrently via `Task.async_stream/3`
  with `ordered: true`, so the returned results are always in original input order — one
  result per input item, tagged with its zero-based index. Each item is independent, so the
  operation is always partial: failures, validation errors, and timeouts affect only their
  own item and never roll back successful inserts.

  Two optional test hooks simulate real work: `"delay"` (milliseconds the insert takes) and
  `"fail"` (truthy → the insert fails). An item whose work exceeds `:timeout_ms` is killed
  and reported as `:timeout`; it is not inserted.
  """

  @type attrs :: %{optional(String.t()) => term()}
  @type item :: %{id: pos_integer(), name: String.t(), price: pos_integer()}
  @type reason :: {:validation, %{atom() => [String.t()]}} | :insert_failed | :timeout
  @type result :: {non_neg_integer(), :ok, item()} | {non_neg_integer(), :error, reason()}

  @default_max_concurrency 4
  @default_timeout_ms 1000
  @name_min 1
  @name_max 100

  @doc """
  Starts the catalog `Agent` registered under `ConcurrentCatalog`.

  The initial state holds no items, a next id of `1`, and a zeroed running/peak counter.
  """
  @spec start_link() :: Agent.on_start()
  def start_link do
    Agent.start_link(fn -> %{items: %{}, next_id: 1, running: 0, peak: 0} end, name: __MODULE__)
  end

  @doc """
  Returns all stored items, sorted by ascending id.
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
  Returns the stored item with the given `id`, or `nil` when no such item exists.
  """
  @spec get(term()) :: item() | nil
  def get(id) do
    Agent.get(__MODULE__, fn state -> Map.get(state.items, id) end)
  end

  @doc """
  Returns the high-water mark of simultaneously-running item tasks observed so far.

  This never exceeds the `:max_concurrency` used by `bulk_create/2`.
  """
  @spec peak() :: non_neg_integer()
  def peak do
    Agent.get(__MODULE__, fn state -> state.peak end)
  end

  @doc """
  Concurrently validates and inserts each attribute map in `list_of_attrs`.

  Options:

    * `:max_concurrency` — at most this many item tasks run at once (default `#{@default_max_concurrency}`)
    * `:timeout_ms` — per-item time budget; an item exceeding it is killed (default `#{@default_timeout_ms}`)

  Returns a plain list of results in original input order, exactly one per input item:

    * `{index, :ok, item}` — the item was validated and inserted
    * `{index, :error, {:validation, errors_map}}` — the attributes were invalid
    * `{index, :error, :insert_failed}` — the insert hook was told to fail, or the task crashed
    * `{index, :error, :timeout}` — the item's work exceeded `:timeout_ms` and was killed

  ## Examples

      iex> {:ok, _pid} = ConcurrentCatalog.start_link()
      iex> ConcurrentCatalog.bulk_create([%{"name" => "Cog", "price" => 5}])
      [{0, :ok, %{id: 1, name: "Cog", price: 5}}]

  """
  @spec bulk_create([attrs()], keyword()) :: [result()]
  def bulk_create(list_of_attrs, opts \\ []) when is_list(list_of_attrs) do
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

  # Runs one item end to end: validate, then insert while tracking the concurrency mark.
  @spec process_item(attrs(), non_neg_integer()) :: result()
  defp process_item(attrs, index) do
    case validate(attrs) do
      {:ok, valid} -> tracked(fn -> insert(valid, index) end)
      {:error, errors} -> {index, :error, {:validation, errors}}
    end
  end

  # Marks a task as running for the duration of `fun`, updating the high-water mark.
  #
  # The decrement is registered with `Process.flag(:trap_exit, ...)`-free cleanup via a
  # monitoring helper: because a timed-out task is killed, we cannot rely on the task itself
  # to decrement. Instead the Agent decrements when it observes the task's DOWN message.
  @spec tracked((-> result())) :: result()
  defp tracked(fun) do
    :ok = enter()

    try do
      fun.()
    after
      leave()
    end
  end

  # Increments the running counter, updates the peak, and asks the Agent to watch this task
  # so that a killed task still gets its counter decremented.
  @spec enter() :: :ok
  defp enter do
    task = self()

    Agent.update(__MODULE__, fn state ->
      running = state.running + 1
      Process.monitor(task)
      %{state | running: running, peak: max(state.peak, running)}
    end)
  end

  # Decrements the running counter for a task that finished normally. The Agent guards
  # against a double decrement from the subsequent DOWN message via the monitor bookkeeping
  # in `handle_down/2`, which only fires for tasks that never called `leave/0`.
  @spec leave() :: :ok
  defp leave do
    task = self()

    Agent.update(__MODULE__, fn state ->
      flush_downs(state)
      |> release(task)
    end)
  end

  # Drains any DOWN messages sitting in the Agent's mailbox, decrementing for each killed
  # task so that the running counter cannot drift upward across bulk_create/2 calls.
  @spec flush_downs(map()) :: map()
  defp flush_downs(state) do
    receive do
      {:DOWN, _ref, :process, _pid, _reason} -> flush_downs(%{state | running: state.running - 1})
    after
      0 -> state
    end
  end

  # Decrements the running counter for `task` and consumes the monitor we set for it.
  @spec release(map(), pid()) :: map()
  defp release(state, task) do
    receive do
      {:DOWN, _ref, :process, ^task, _reason} -> :ok
    after
      0 -> :ok
    end

    %{state | running: max(state.running - 1, 0)}
  end

  # Performs the actual insert, honouring the "delay" and "fail" test hooks.
  @spec insert(map(), non_neg_integer()) :: result()
  defp insert(%{name: name, price: price, delay: delay, fail: fail?}, index) do
    if delay > 0, do: Process.sleep(delay)

    if fail? do
      {index, :error, :insert_failed}
    else
      item =
        Agent.get_and_update(__MODULE__, fn state ->
          item = %{id: state.next_id, name: name, price: price}
          items = Map.put(state.items, item.id, item)
          {item, %{state | items: items, next_id: state.next_id + 1}}
        end)

      {index, :ok, item}
    end
  end

  # Turns an async_stream element into the final, index-tagged result tuple.
  @spec normalize_result({{:ok, result()} | {:exit, term()}, non_neg_integer()}) :: result()
  defp normalize_result({{:ok, result}, _index}), do: result
  defp normalize_result({{:exit, :timeout}, index}), do: {index, :error, :timeout}
  defp normalize_result({{:exit, _reason}, index}), do: {index, :error, :insert_failed}

  # Validates the raw attribute map, returning normalized fields or a map of field errors.
  @spec validate(attrs()) :: {:ok, map()} | {:error, %{atom() => [String.t()]}}
  defp validate(attrs) when is_map(attrs) do
    errors =
      %{}
      |> validate_name(Map.get(attrs, "name"))
      |> validate_price(Map.get(attrs, "price"))

    if map_size(errors) == 0 do
      {:ok,
       %{
         name: Map.fetch!(attrs, "name"),
         price: Map.fetch!(attrs, "price"),
         delay: normalize_delay(Map.get(attrs, "delay")),
         fail: truthy?(Map.get(attrs, "fail"))
       }}
    else
      {:error, errors}
    end
  end

  defp validate(_attrs) do
    {:error, %{base: ["must be a map of attributes"]}}
  end

  @spec validate_name(map(), term()) :: map()
  defp validate_name(errors, nil), do: Map.put(errors, :name, ["can't be blank"])

  defp validate_name(errors, name) when is_binary(name) do
    length = String.length(name)

    cond do
      length < @name_min -> Map.put(errors, :name, ["can't be blank"])
      length > @name_max -> Map.put(errors, :name, ["should be at most #{@name_max} character(s)"])
      true -> errors
    end
  end

  defp validate_name(errors, _name), do: Map.put(errors, :name, ["is invalid"])

  @spec validate_price(map(), term()) :: map()
  defp validate_price(errors, nil), do: Map.put(errors, :price, ["can't be blank"])

  defp validate_price(errors, price) when is_integer(price) do
    if price > 0, do: errors, else: Map.put(errors, :price, ["must be greater than 0"])
  end

  defp validate_price(errors, _price), do: Map.put(errors, :price, ["is invalid"])

  @spec normalize_delay(term()) :: non_neg_integer()
  defp normalize_delay(delay) when is_integer(delay) and delay > 0, do: delay
  defp normalize_delay(_delay), do: 0

  @spec truthy?(term()) :: boolean()
  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(_value), do: true
end