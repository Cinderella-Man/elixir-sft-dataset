defmodule ConcurrencyCounter do
  @moduledoc """
  A GenServer that tracks an active-task count and remembers the highest
  value it has ever reached (the "peak"). Intended for use in tests to
  verify that `ParallelMap.pmap/3` never exceeds its declared concurrency
  limit at runtime.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Starts the counter. Accepts `:name` in `opts`."
  def start_link(opts \\ []) do
    {name, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {__MODULE__, rest}
        {name, rest} -> {name, rest}
      end

    GenServer.start_link(__MODULE__, %{count: 0, peak: 0}, [{:name, name} | server_opts])
  end

  @doc "Increments the active count by 1. Returns the new value."
  def increment(server), do: GenServer.call(server, :increment)

  @doc "Decrements the active count by 1. Returns the new value."
  def decrement(server), do: GenServer.call(server, :decrement)

  @doc "Returns the highest value the counter has ever reached."
  def peak(server), do: GenServer.call(server, :peak)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:increment, _from, %{count: count, peak: peak} = state) do
    new_count = count + 1
    new_state = %{state | count: new_count, peak: max(new_count, peak)}
    {:reply, new_count, new_state}
  end

  def handle_call(:decrement, _from, %{count: count} = state) do
    new_count = count - 1
    {:reply, new_count, %{state | count: new_count}}
  end

  def handle_call(:peak, _from, %{peak: peak} = state) do
    {:reply, peak, state}
  end
end

defmodule ParallelMap do
  @moduledoc """
  Applies a function to every element of a collection in parallel while
  keeping the number of concurrently running tasks at or below
  `max_concurrency`.

  Results are always returned in the same order as the input. If the
  function raises or the spawned process exits abnormally, the corresponding
  result is `{:error, reason}`; all other in-flight tasks continue
  unaffected.

  Scheduling is implemented with `Task.async`/`Task.yield_many` over a
  sliding window of at most `max_concurrency` tasks. `Task.async` links the
  task to the caller, so exits are trapped for the duration of the run (and
  restored afterwards): a crashing task then surfaces as a harmless
  `{:exit, reason}` yield result instead of killing the caller.
  """

  @doc """
  Maps `func` over `collection` in parallel, with at most `max_concurrency`
  tasks alive at any one time.

  ## Examples

      iex> ParallelMap.pmap(1..5, fn x -> x * 2 end, 2)
      [2, 4, 6, 8, 10]

      iex> ParallelMap.pmap([1, :boom, 3], fn
      ...>   :boom -> raise "oops"
      ...>   x    -> x * 10
      ...> end, 2)
      [10, {:error, _}, 30]
  """
  @spec pmap(Enumerable.t(), (term() -> term()), pos_integer()) :: [term()]
  def pmap(collection, func, max_concurrency)
      when is_function(func, 1) and is_integer(max_concurrency) and max_concurrency >= 1 do
    indexed = collection |> Enum.to_list() |> Enum.with_index()
    total = length(indexed)

    if total == 0 do
      []
    else
      # `Task.async` links each task to this process; trap exits so an
      # abnormally exiting task delivers a message instead of killing us,
      # then restore the flag and drain those messages before returning.
      was_trapping? = Process.flag(:trap_exit, true)

      try do
        {seed, queue} = Enum.split(indexed, max_concurrency)

        # running: %{%Task{} => original_index}
        running = Map.new(seed, fn {elem, idx} -> {start_task(func, elem), idx} end)

        raw = collect(running, queue, func, _results = %{})

        # Reassemble in original order.
        Enum.map(0..(total - 1), fn i -> Map.fetch!(raw, i) end)
      after
        Process.flag(:trap_exit, was_trapping?)
        flush_exit_messages()
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp start_task(func, elem), do: Task.async(fn -> func.(elem) end)

  # Base case: nothing running and nothing queued.
  defp collect(running, [] = _queue, _func, results) when map_size(running) == 0,
    do: results

  # The as-they-finish loop: harvest whatever `Task.yield_many/2` reports in
  # this tick — a normal reply (`{:ok, value}`) or a crash (`{:exit, reason}`,
  # covering raises, abnormal exits, throws and external kills alike) — then
  # refill the freed slots from the queue and go again.
  defp collect(running, queue, func, results) do
    finished =
      running
      |> Map.keys()
      |> Task.yield_many(20)
      |> Enum.filter(fn {_task, res} -> res != nil end)

    case finished do
      [] ->
        collect(running, queue, func, results)

      finished ->
        Enum.reduce(finished, {running, queue, results}, fn {task, res}, {run, q, acc} ->
          idx = Map.fetch!(run, task)

          outcome =
            case res do
              {:ok, value} -> value
              {:exit, reason} -> {:error, reason}
            end

          run = Map.delete(run, task)
          acc = Map.put(acc, idx, outcome)

          case q do
            [] ->
              {run, [], acc}

            [{elem, next_idx} | rest] ->
              {Map.put(run, start_task(func, elem), next_idx), rest, acc}
          end
        end)
        |> then(fn {run, q, acc} -> collect(run, q, func, acc) end)
    end
  end

  # Trapped exits from finished/crashed tasks land in our mailbox; drain them
  # so pmap leaves the caller's mailbox exactly as it found it.
  defp flush_exit_messages do
    receive do
      {:EXIT, _pid, _reason} -> flush_exit_messages()
    after
      0 -> :ok
    end
  end
end
