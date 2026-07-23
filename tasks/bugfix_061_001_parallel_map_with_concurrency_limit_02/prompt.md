# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

Write me an Elixir module called `ParallelMap` that applies a function to a collection
in parallel while enforcing a maximum concurrency limit.

I need one public function:
- `ParallelMap.pmap(collection, func, max_concurrency)` which applies `func` to each
  element of `collection` in parallel, with at most `max_concurrency` tasks running at
  the same time. It must return results in the same order as the input collection,
  regardless of completion order.

Task crash handling: if `func` raises or the spawned task exits abnormally for a given
element, that element's result should be `{:error, reason}` — this must not affect or
cancel other in-flight tasks.

For concurrency enforcement: use a pool/semaphore approach so that at no point are more
than `max_concurrency` tasks alive simultaneously. A new task should only be spawned once
a running one has finished (or crashed).

You will also need to write a helper GenServer called `ConcurrencyCounter` in the same
file. It must expose:
- `ConcurrencyCounter.start_link(opts)` — starts the process, accepts `:name`
- `ConcurrencyCounter.increment(server)` — increments the active count, returns the new value
- `ConcurrencyCounter.decrement(server)` — decrements the active count, returns the new value
- `ConcurrencyCounter.peak(server)` — returns the highest value the counter has ever reached

`ConcurrencyCounter` is intended for use in tests to verify the concurrency limit is
actually respected at runtime — your `pmap` implementation itself does not need to use it.

`pmap` must be mailbox-safe for the calling process: consume only messages that
belong to the tasks it spawned. If the caller is trapping exits, any unrelated
`{:EXIT, pid, reason}` messages it held (or receives while `pmap` runs) must still
be in its mailbox when `pmap` returns, and the caller's `:trap_exit` flag must be
left exactly as `pmap` found it.

Give me the complete implementation in a single file. Use only OTP and the standard
library — no external dependencies. Do not use `Task.async_stream`; implement the
scheduling logic yourself using `Task.async` / `Task.yield`.

## The buggy module

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
      was_trapping? = Process.flag(:trap_exit, false)

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

  # Base case: nothing running and nothing queued.
  defp collect(running, [] = _queue, _func, results, pids) when map_size(running) == 0,
    do: {results, pids}

  # The as-they-finish loop: harvest whatever `Task.yield_many/2` reports in
  # this tick — a normal reply (`{:ok, value}`) or a crash (`{:exit, reason}`,
  # covering raises, abnormal exits, throws and external kills alike) — then
  # refill the freed slots from the queue and go again.
  defp collect(running, queue, func, results, pids) do
    finished =
      running
      |> Map.keys()
      |> Task.yield_many(20)
      |> Enum.filter(fn {_task, res} -> res != nil end)

    case finished do
      [] ->
        collect(running, queue, func, results, pids)

      finished ->
        finished
        |> Enum.reduce({running, queue, results, pids}, fn {task, res}, {run, q, acc, ps} ->
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
              {run, [], acc, ps}

            [{elem, next_idx} | rest] ->
              refill = start_task(func, elem)
              {Map.put(run, refill, next_idx), rest, acc, Map.put(ps, refill.pid, true)}
          end
        end)
        |> then(fn {run, q, acc, ps} -> collect(run, q, func, acc, ps) end)
    end
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

## Failing test report

```
8 of 20 test(s) failed:

  * test a crashing function returns {:error, reason} for that item
      {:EXIT, #PID<0.270.0>}: {%RuntimeError{message: "boom"}, [{ParallelMapTest, :"-test a crashing function returns {:error, reason} for that item/1-fun-0-", 1, [file: ~c".gen_staging/stage_bugfix_061_001_parallel_map_with_concurrency_limit_02/test_harness.exs", line: 108, error_info: %{module: Exception}]}, {Task.Supervised, :invoke_mfa, 2, [file: ~c"lib/task/supervised.ex", line: 105]}, {Task.Supervised, :reply, 4, [file: ~c"lib/task/supervised.ex", line: 40]}]}

  * test crash in one task does not cancel other tasks
      {:EXIT, #PID<0.274.0>}: {%RuntimeError{message: "only me"}, [{ParallelMapTest, :"-test crash in one task does not cancel other tasks/1-fun-0-", 1, [file: ~c".gen_staging/stage_bugfix_061_001_parallel_map_with_concurrency_limit_02/test_harness.exs", line: 124, error_info: %{module: Exception}]}, {Task.Supervised, :invoke_mfa, 2, [file: ~c"lib/task/supervised.ex", line: 105]}, {Task.Supervised, :reply, 4, [file: ~c"lib/task/supervised.ex", line: 40]}]}

  * test all items crash — returns all error tuples
      {:EXIT, #PID<0.280.0>}: {%RuntimeError{message: "always"}, [{ParallelMapTest, :"-test all items crash — returns all error tuples/1-fun-0-", 1, [file: ~c".gen_staging/stage_bugfix_061_001_parallel_map_with_concurrency_limit_02/test_harness.exs", line: 138, error_info: %{module: Exception}]}, {Task.Supervised, :invoke_mfa, 2, [file: ~c"lib/task/supervised.ex", line: 105]}, {Task.Supervised, :reply, 4, [file: ~c"lib/task/supervised.ex", line: 40]}]}

  * test an exiting function returns {:error, reason} for that item only
      {:EXIT, #PID<0.290.0>}: :no_thanks

  (…4 more)
```
