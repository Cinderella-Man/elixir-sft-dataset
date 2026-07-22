defmodule WeightedMap do
  @moduledoc """
  Parallel `map` where concurrency is bounded by a **weight budget** instead of
  a task count.

  Each element is assigned a positive integer weight by a `weight_fun`. Elements
  are applied to `func` concurrently such that the sum of the weights of all
  in-flight tasks never exceeds a fixed `budget`.

  Admission is strictly head-of-line, in input order: a queued element only
  starts once the currently running total weight plus its own weight fits within
  the budget. As a special case, an element whose weight is larger than the whole
  budget would otherwise never run, so it is allowed to run alone — only while
  nothing else is running.

  Results are returned in the same order as the input, regardless of the order in
  which tasks complete. If `func` raises, or the spawned task exits abnormally,
  the corresponding result is `{:error, reason}` and that element's weight is
  released back to the budget without disturbing other in-flight tasks.

  The scheduling logic is implemented directly with `spawn_monitor/1`; it does
  not use `Task.async_stream/3`.

  The companion `WeightMeter` GenServer is a small instrumentation helper for
  tests that wish to assert the budget is respected at runtime.
  """

  @typedoc "Internal per-element entry: `{index, element, weight}`."
  @type entry :: {non_neg_integer(), term(), pos_integer()}

  @doc """
  Applies `func` to every element of `collection` in parallel under a weight
  budget.

  `weight_fun` must return a positive integer for each element and `budget` must
  be a positive integer; otherwise an `ArgumentError` is raised before any task
  is started. Results are returned in input order. An element whose task crashes
  yields `{:error, reason}`.
  """
  @spec pmap(Enumerable.t(), (term() -> term()), (term() -> pos_integer()), pos_integer()) ::
          [term()]
  def pmap(collection, func, weight_fun, budget) do
    validate_budget!(budget)
    entries = validate!(collection, weight_fun)

    state = %{
      pending: entries,
      running: %{},
      total: 0,
      results: %{},
      budget: budget,
      func: func
    }

    results = loop(admit(state))
    Enum.map(entries, fn {index, _elem, _weight} -> Map.fetch!(results, index) end)
  end

  @spec validate_budget!(term()) :: :ok
  defp validate_budget!(budget) when is_integer(budget) and budget > 0, do: :ok

  defp validate_budget!(budget) do
    raise ArgumentError, "budget must be a positive integer, got: #{inspect(budget)}"
  end

  @spec validate!(Enumerable.t(), (term() -> pos_integer())) :: [entry()]
  defp validate!(collection, weight_fun) do
    collection
    |> Enum.with_index()
    |> Enum.map(fn {elem, index} ->
      weight = weight_fun.(elem)

      if is_integer(weight) and weight > 0 do
        {index, elem, weight}
      else
        raise ArgumentError,
              "weight_fun must return a positive integer, got: #{inspect(weight)}"
      end
    end)
  end

  @spec loop(map()) :: %{optional(non_neg_integer()) => term()}
  defp loop(%{pending: [], running: running, results: results}) when map_size(running) == 0 do
    results
  end

  defp loop(state) do
    receive do
      {:done, pid, result} ->
        {index, weight} = Map.fetch!(state.running, pid)

        state = %{
          state
          | running: Map.delete(state.running, pid),
            total: state.total - weight,
            results: Map.put(state.results, index, result)
        }

        loop(admit(state))

      {:DOWN, _ref, :process, pid, reason} ->
        case Map.fetch(state.running, pid) do
          {:ok, {index, weight}} ->
            state = %{
              state
              | running: Map.delete(state.running, pid),
                total: state.total - weight,
                results: Map.put(state.results, index, {:error, reason})
            }

            loop(admit(state))

          :error ->
            # Normal-exit :DOWN that follows an already-handled {:done, ...}.
            loop(state)
        end
    end
  end

  @spec admit(map()) :: map()
  defp admit(%{pending: []} = state), do: state

  defp admit(%{pending: [{index, elem, weight} | rest]} = state) do
    cond do
      state.total + weight <= state.budget ->
        admit(start_task(%{state | pending: rest}, index, elem, weight))

      weight > state.budget and map_size(state.running) == 0 ->
        admit(start_task(%{state | pending: rest}, index, elem, weight))

      true ->
        state
    end
  end

  @spec start_task(map(), non_neg_integer(), term(), pos_integer()) :: map()
  defp start_task(state, index, elem, weight) do
    parent = self()
    func = state.func

    {pid, _ref} =
      spawn_monitor(fn ->
        send(parent, {:done, self(), func.(elem)})
      end)

    %{
      state
      | running: Map.put(state.running, pid, {index, weight}),
        total: state.total + weight
    }
  end
end

defmodule WeightMeter do
  @moduledoc """
  A tiny GenServer that tracks a running in-flight weight total and records the
  peak value ever observed.

  It is meant for tests that want to assert `WeightedMap.pmap/4` never exceeds
  its weight budget: call `add/2` when a task starts, `sub/2` when it finishes,
  and inspect `peak/1` afterwards.
  """

  use GenServer

  @typedoc "Internal server state."
  @type state :: %{total: integer(), peak: integer()}

  @doc """
  Starts the meter. Accepts a `:name` option to register the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{total: 0, peak: 0}, gen_opts)
  end

  @doc """
  Adds `weight` to the in-flight total and returns the new total.
  """
  @spec add(GenServer.server(), integer()) :: integer()
  def add(server, weight), do: GenServer.call(server, {:add, weight})

  @doc """
  Subtracts `weight` from the in-flight total and returns the new total.
  """
  @spec sub(GenServer.server(), integer()) :: integer()
  def sub(server, weight), do: GenServer.call(server, {:sub, weight})

  @doc """
  Returns the highest in-flight total the meter has ever reached.
  """
  @spec peak(GenServer.server()) :: integer()
  def peak(server), do: GenServer.call(server, :peak)

  @impl true
  @spec init(state()) :: {:ok, state()}
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:add, weight}, _from, %{total: total, peak: peak} = state) do
    new_total = total + weight
    {:reply, new_total, %{state | total: new_total, peak: max(peak, new_total)}}
  end

  def handle_call({:sub, weight}, _from, %{total: total} = state) do
    new_total = total - weight
    {:reply, new_total, %{state | total: new_total}}
  end

  def handle_call(:peak, _from, %{peak: peak} = state) do
    {:reply, peak, state}
  end
end