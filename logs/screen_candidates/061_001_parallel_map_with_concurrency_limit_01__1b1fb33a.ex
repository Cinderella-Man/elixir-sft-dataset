defmodule ConcurrencyCounter do
  @moduledoc """
  A small GenServer that tracks how many things are currently active, along with the
  highest value that count has ever reached.

  It is primarily intended as a test aid: increment on entry to a critical section and
  decrement on exit, then assert that `peak/1` never exceeded the limit you expected.

  Example:

      {:ok, counter} = ConcurrencyCounter.start_link(name: :my_counter)
      ConcurrencyCounter.increment(:my_counter)
      ConcurrencyCounter.decrement(:my_counter)
      ConcurrencyCounter.peak(:my_counter)
      #=> 1

  All operations are synchronous calls, so the counter is safe to use from many
  processes at once: updates are serialized by the GenServer itself.
  """

  use GenServer

  @typedoc "A reference to a running `ConcurrencyCounter` process."
  @type server :: GenServer.server()

  defstruct active: 0, peak: 0

  @doc """
  Starts a counter process.

  Accepts the usual `GenServer` options; in particular `:name` may be given to register
  the process. The counter starts with an active count and a peak of `0`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, _rest} = Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])
    GenServer.start_link(__MODULE__, :ok, gen_opts)
  end

  @doc """
  Increments the active count by one and returns the new value.

  If the new value exceeds the recorded peak, the peak is raised to match.
  """
  @spec increment(server()) :: non_neg_integer()
  def increment(server) do
    GenServer.call(server, :increment)
  end

  @doc """
  Decrements the active count by one and returns the new value.

  The count is clamped at `0`, so extra decrements never make it go negative. The peak is
  left untouched.
  """
  @spec decrement(server()) :: non_neg_integer()
  def decrement(server) do
    GenServer.call(server, :decrement)
  end

  @doc """
  Returns the highest value the active count has ever reached.
  """
  @spec peak(server()) :: non_neg_integer()
  def peak(server) do
    GenServer.call(server, :peak)
  end

  @impl GenServer
  def init(:ok) do
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call(:increment, _from, %__MODULE__{} = state) do
    active = state.active + 1
    peak = max(state.peak, active)
    {:reply, active, %__MODULE__{state | active: active, peak: peak}}
  end

  def handle_call(:decrement, _from, %__MODULE__{} = state) do
    active = max(state.active - 1, 0)
    {:reply, active, %__MODULE__{state | active: active}}
  end

  def handle_call(:peak, _from, %__MODULE__{} = state) do
    {:reply, state.peak, state}
  end
end

defmodule ParallelMap do
  @moduledoc """
  Parallel `map` with a hard cap on how many tasks may run at once.

  `pmap/3` walks a collection, applying a function to every element in a separate task,
  but never allows more than `max_concurrency` tasks to be alive at the same time. A new
  task is only started after a running one has finished — successfully or not.

  Results come back in input order, independent of the order in which tasks completed.

  Failures are isolated: if the function raises, throws, or the task exits abnormally, that
  single element yields `{:error, reason}` and every other task keeps running untouched.

      ParallelMap.pmap([1, 2, 3], &(&1 * 2), 2)
      #=> [2, 4, 6]

      ParallelMap.pmap([1, 0, 3], &div(10, &1), 2)
      #=> [10, {:error, %ArithmeticError{}}, 30]

  The scheduling is implemented directly on top of `Task.async/1` and `Task.yield_many/2`;
  `Task.async_stream/3` is deliberately not used.
  """

  @typedoc """
  The outcome for a single element: either the raw value returned by the function, or
  `{:error, reason}` if that element's task failed.
  """
  @type result :: term() | {:error, term()}

  @yield_interval 50

  @doc """
  Applies `func` to each element of `collection` in parallel, running at most
  `max_concurrency` tasks simultaneously.

  Returns a list of results in the same order as the input, regardless of the order in
  which the tasks completed.

  If the task for an element raises, throws, or exits abnormally, that position holds
  `{:error, reason}` instead of a value. `reason` is the exception struct for a raise, and
  the exit reason otherwise. Other tasks are neither cancelled nor affected.

  `max_concurrency` must be a positive integer. An empty collection returns `[]` without
  spawning anything.

  ## Examples

      iex> ParallelMap.pmap([1, 2, 3, 4], &(&1 * &1), 2)
      [1, 4, 9, 16]

      iex> ParallelMap.pmap([], &(&1), 4)
      []
  """
  @spec pmap(Enumerable.t(), (term() -> term()), pos_integer()) :: [result()]
  def pmap(collection, func, max_concurrency)
      when is_function(func, 1) and is_integer(max_concurrency) and max_concurrency > 0 do
    collection
    |> Enum.with_index()
    |> schedule(func, max_concurrency, %{}, [])
    |> Enum.sort_by(fn {index, _result} -> index end)
    |> Enum.map(fn {_index, result} -> result end)
  end

  # Core loop. `pending` is the list of {element, index} not yet started, `running` maps
  # task ref => index, and `done` accumulates {index, result} pairs.
  @spec schedule([{term(), non_neg_integer()}], (term() -> term()), pos_integer(), map(), [
          {non_neg_integer(), result()}
        ]) :: [{non_neg_integer(), result()}]
  defp schedule([], _func, _max, running, done) when map_size(running) == 0 do
    done
  end

  defp schedule(pending, func, max, running, done) do
    {running, pending} = start_tasks(pending, func, max, running)
    {running, done} = await_one(running, done)
    schedule(pending, func, max, running, done)
  end

  # Spawns tasks until either the pending list is exhausted or the concurrency cap is hit.
  @spec start_tasks([{term(), non_neg_integer()}], (term() -> term()), pos_integer(), map()) ::
          {map(), [{term(), non_neg_integer()}]}
  defp start_tasks([{element, index} | rest], func, max, running) when map_size(running) < max do
    task = Task.async(fn -> func.(element) end)
    start_tasks(rest, func, max, Map.put(running, task.ref, {task, index}))
  end

  defp start_tasks(pending, _func, _max, running) do
    {running, pending}
  end

  # Blocks until at least one running task settles, then records every task that settled.
  @spec await_one(map(), [{non_neg_integer(), result()}]) ::
          {map(), [{non_neg_integer(), result()}]}
  defp await_one(running, done) when map_size(running) == 0 do
    {running, done}
  end

  defp await_one(running, done) do
    tasks = Enum.map(running, fn {_ref, {task, _index}} -> task end)

    case Task.yield_many(tasks, @yield_interval) do
      [] ->
        {running, done}

      answers ->
        settled = Enum.reject(answers, fn {_task, outcome} -> is_nil(outcome) end)
        collect(settled, running, done)
    end
  end

  # Folds settled tasks into the accumulator, removing them from the running map. If none
  # settled within the yield interval we simply loop again, so the caller never busy-waits
  # on an empty result.
  @spec collect([{Task.t(), term()}], map(), [{non_neg_integer(), result()}]) ::
          {map(), [{non_neg_integer(), result()}]}
  defp collect([], running, done) do
    await_one(running, done)
  end

  defp collect(settled, running, done) do
    Enum.reduce(settled, {running, done}, fn {task, outcome}, {acc_running, acc_done} ->
      {{^task, index}, acc_running} = Map.pop(acc_running, task.ref)
      {acc_running, [{index, normalize(outcome)} | acc_done]}
    end)
  end

  # Turns a `Task.yield_many/2` outcome into either the plain value or `{:error, reason}`.
  @spec normalize({:ok, term()} | {:exit, term()}) :: result()
  defp normalize({:ok, value}), do: value
  defp normalize({:exit, {%{__exception__: true} = exception, _stack}}), do: {:error, exception}
  defp normalize({:exit, reason}), do: {:error, reason}
end