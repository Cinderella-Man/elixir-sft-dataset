Implement the private `collect/5` function.

`collect(running, queue, func, parent, results)` is the recursive scheduling loop
that drives `ParallelMap.pmap/3`. Its arguments are:

- `running` — a map of currently in-flight tasks, keyed by our own `make_ref()`
  value, where each value is `{monitor_ref, original_index}`.
- `queue` — the list of not-yet-started `{elem, index}` pairs still waiting for a
  free concurrency slot.
- `func` — the 1-arity function being mapped over the collection.
- `parent` — the pid that spawned tasks send their result messages to (the caller).
- `results` — a map accumulating completed outcomes, keyed by original index.

It must behave as follows:

1. **Base case.** When there is nothing left running *and* nothing left queued
   (`running` is empty and `queue` is `[]`), return the accumulated `results` map.

2. **Recursive case.** Otherwise, block until exactly one running task finishes by
   calling `await_one/1`, which returns `{finished_ref, finished_idx, outcome}`.
   - Record the outcome in `results` under `finished_idx`.
   - Remove `finished_ref` from `running` (its slot is now free).
   - Immediately refill the freed slot: if `queue` is non-empty, pop its head
     `{elem, idx}`, spawn a new task with `spawn_task/3`, and add the returned
     `{our_ref, mon_ref}` to `running` (keyed by `our_ref`, value `{mon_ref, idx}`);
     if `queue` is empty, leave `running` as-is.
   - Recurse with the updated `running`, remaining `queue`, and updated `results`.

This structure guarantees that a new task is only spawned once a running one has
finished, so at no point are more than `max_concurrency` tasks alive at once, while
`results` is keyed by original index so the final output can be reassembled in order.

```elixir
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

        pids = Map.new(Map.keys(running), &{&1.pid, true})
        {raw, pids} = collect(running, queue, func, _results = %{}, pids)

        # Reassemble in original order.
        result = Enum.map(0..(total - 1), fn i -> Map.fetch!(raw, i) end)
        Process.flag(:trap_exit, was_trapping?)
        # Drain ONLY our own tasks' exits: a trapping caller may hold
        # unrelated {:EXIT, ...} mail of its own that pmap must not eat.
        flush_exit_messages(pids)
        result
      after
        Process.flag(:trap_exit, was_trapping?)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp start_task(func, elem), do: Task.async(fn -> func.(elem) end)

  defp collect(running, [] = _queue, _func, results, pids) when map_size(running) == 0 do
    # TODO
  end

  # Trapped exits from finished/crashed tasks land in our mailbox; drain
  # exactly THOSE (matched by task pid) so pmap leaves the caller's mailbox
  # as it found it — including any unrelated {:EXIT, ...} a trapping caller
  # was already holding.
  defp flush_exit_messages(pids) do
    receive do
      {:EXIT, pid, _reason} when is_map_key(pids, pid) -> flush_exit_messages(pids)
    after
      0 -> :ok
    end
  end
end
```