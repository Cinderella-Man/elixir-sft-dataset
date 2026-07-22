# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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

## New specification

Write me an Elixir module called `RetryMap` that applies a function to a collection in
parallel, enforcing a maximum concurrency limit **and** giving each element a per-attempt
timeout with bounded retries.

I need one public function:
- `RetryMap.pmap(collection, func, opts)` where `opts` is a keyword list accepting:
  - `:max_concurrency` — the maximum number of tasks alive at once (default `5`)
  - `:timeout` — the per-attempt timeout in milliseconds (default `5000`)
  - `:max_attempts` — the maximum number of attempts per element (default `1`)

It applies `func` to each element in parallel with at most `max_concurrency` tasks alive
simultaneously, and returns a list — in the **same order** as the input — of tagged
results, one per element.

Per-element semantics:
- If an attempt returns a value within `:timeout`, that element's result is `{:ok, value}`.
- If an attempt does **not** finish within `:timeout`, kill that attempt and retry, up to a
  total of `:max_attempts` attempts. If all attempts time out, the result is
  `{:error, :timeout}`.
- If `func` raises (or the task exits abnormally), that is a **permanent** failure — do
  **not** retry — and the result is `{:error, {:exception, reason}}` (or a similarly tagged
  error for a non-exception failure). A crash or timeout for one element must not affect any
  other element.

For concurrency enforcement: use a pool/semaphore approach so that at no point are more than
`max_concurrency` tasks alive simultaneously. A freed slot is filled from the queue once an
element reaches a terminal result; a retry of a timed-out element reuses that element's slot.

You will also need to write a helper GenServer called `ConcurrencyCounter` in the same file.
It must expose:
- `ConcurrencyCounter.start_link(opts)` — starts the process, accepts `:name`
- `ConcurrencyCounter.increment(server)` — increments the active count, returns the new value
- `ConcurrencyCounter.decrement(server)` — decrements the active count, returns the new value
- `ConcurrencyCounter.peak(server)` — returns the highest value the counter has ever reached

`ConcurrencyCounter` is intended for use in tests to verify the concurrency limit is actually
respected at runtime; your `pmap` implementation itself does not need to use it.

Give me the complete implementation in a single file. Use only OTP and the standard library —
no external dependencies. Do not use `Task.async_stream`; implement the scheduling, timeout,
and retry logic yourself using `spawn_monitor`, `Process.send_after`, and `Process.exit`.
