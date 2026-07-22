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
        {nil, rest}    -> {__MODULE__, rest}
        {name, rest}   -> {name, rest}
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

  Scheduling is implemented with `spawn_monitor` rather than `Task.async`
  so that task crashes never propagate as exit signals to the caller —
  only a `:DOWN` monitor message is delivered.
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
    total   = length(indexed)

    if total == 0 do
      []
    else
      parent          = self()
      {seed, queue}   = Enum.split(indexed, max_concurrency)

      # running: %{our_ref => {monitor_ref, original_index}}
      #
      # We use our own `make_ref()` as the primary key because it is the
      # value embedded in the result message that the spawned process sends
      # back.  The monitor ref is kept alongside so we can demonitor cleanly
      # after receiving the result.
      running =
        Map.new(seed, fn {elem, idx} ->
          {our_ref, mon_ref} = spawn_task(parent, func, elem)
          {our_ref, {mon_ref, idx}}
        end)

      raw = collect(running, queue, func, parent, _results = %{})

      # Reassemble in original order.
      Enum.map(0..(total - 1), fn i -> Map.fetch!(raw, i) end)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Spawns a monitored (but NOT linked) process that runs `func.(elem)`.
  #
  # All exceptions and exits are caught inside the spawned process and
  # converted into a tagged result message sent to `parent`.  This means
  # the process always exits with reason `:normal`, so the `:DOWN` message
  # we will eventually receive is harmless and can simply be flushed.
  #
  # Returns `{our_ref, monitor_ref}`.
  defp spawn_task(parent, func, elem) do
    our_ref = make_ref()

    {_pid, mon_ref} =
      spawn_monitor(fn ->
        result =
          try do
            {:ok, func.(elem)}
          rescue
            e -> {:error, {e, __STACKTRACE__}}
          catch
            :exit,  r -> {:error, r}
            :throw, t -> {:error, {:throw, t}}
          end

        send(parent, {our_ref, result})
      end)

    {our_ref, mon_ref}
  end

  # The recursive scheduling loop. Awaits one finished task at a time,
  # records its outcome by original index, frees its slot, and refills that
  # slot from the queue until nothing is running and nothing is queued.
  defp collect(running, queue, func, parent, results) do
    # TODO
  end

  # Blocks until a message arrives from one of our running tasks.
  #
  # Two cases:
  #   1. `{our_ref, result}` — the task completed (normally or via our
  #      try/catch wrapper) and reported its outcome.  We demonitor with
  #      `:flush` to discard the subsequent `:normal` DOWN message.
  #
  #   2. `{:DOWN, mon_ref, …, reason}` — the process was killed externally
  #      (e.g. a brutal `Process.exit(pid, :kill)`) before it could send a
  #      result message.  We locate the entry by monitor ref and wrap the
  #      reason in `{:error, …}`.
  #
  # Any unrelated message is left to fall through and we recurse.
  defp await_one(running) do
    receive do
      {our_ref, result} when is_map_key(running, our_ref) ->
        {mon_ref, idx} = Map.fetch!(running, our_ref)
        Process.demonitor(mon_ref, [:flush])

        outcome =
          case result do
            {:ok, value}      -> value
            {:error, reason}  -> {:error, reason}
          end

        {our_ref, idx, outcome}

      {:DOWN, mon_ref, :process, _pid, reason} ->
        # Unexpected external kill — locate the task by its monitor ref.
        case Enum.find(running, fn {_ref, {mon, _idx}} -> mon == mon_ref end) do
          {our_ref, {_mon, idx}} -> {our_ref, idx, {:error, reason}}
          nil                    -> await_one(running)
        end

      _other ->
        await_one(running)
    end
  end
end
```