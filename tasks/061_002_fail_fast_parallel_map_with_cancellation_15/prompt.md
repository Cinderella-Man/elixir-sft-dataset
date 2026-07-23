# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `start_link` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

Write me an Elixir module called `FailFastMap` that applies a function to a collection
in parallel with a maximum concurrency limit, but using **fail-fast** semantics instead
of collecting per-element errors.

I need one public function:
- `FailFastMap.pmap(collection, func, max_concurrency)` which applies `func` to each
  element of `collection` in parallel, with at most `max_concurrency` tasks running at
  the same time.

Result semantics (this is the key difference from a normal parallel map):
- If **every** element succeeds, return `{:ok, results}` where `results` is the list of
  return values in the **same order** as the input collection.
- If **any** element's `func` raises or its task exits abnormally, immediately
  short-circuit: return `{:error, {index, reason}}` where `index` is the zero-based
  position of the failing element and `reason` describes the failure. As soon as a
  failure is detected you must **cancel all still-running tasks** (kill their processes)
  and you must **not** start any queued elements that had not yet begun.
- An empty collection returns `{:ok, []}`.

For concurrency enforcement: use a pool/semaphore approach so that at no point are more
than `max_concurrency` tasks alive simultaneously. A new task should only be spawned once
a running one has finished (or when you are still filling the initial window).

You will also need to write a helper GenServer called `ConcurrencyCounter` in the same
file. It must expose:
- `ConcurrencyCounter.start_link(opts)` — starts the process, accepts `:name`
- `ConcurrencyCounter.increment(server)` — increments the active count, returns the new value
- `ConcurrencyCounter.decrement(server)` — decrements the active count, returns the new value
- `ConcurrencyCounter.peak(server)` — returns the highest value the counter has ever reached
- `ConcurrencyCounter.started(server)` — returns how many times `increment/1` has ever been called

`ConcurrencyCounter` is intended for use in tests to verify both the concurrency limit and
that queued work is genuinely cancelled after a failure; your `pmap` implementation itself
does not need to use it.

Give me the complete implementation in a single file. Use only OTP and the standard
library — no external dependencies. Do not use `Task.async_stream`; implement the
scheduling and cancellation logic yourself using `spawn_monitor` / `Process.exit`.

## The module with `start_link` missing

```elixir
defmodule ConcurrencyCounter do
  @moduledoc """
  A GenServer that tracks an active-task count, the highest value it has ever
  reached (`peak`), and the total number of times it was incremented
  (`started`). Intended for tests to verify that `FailFastMap.pmap/3` respects
  its concurrency limit and cancels queued work after a failure.
  """

  use GenServer

  def start_link(opts \\ []) do
    # TODO
  end

  @doc "Increments the active count and returns the new value."
  @spec increment(GenServer.server()) :: integer()
  def increment(server), do: GenServer.call(server, :increment)

  @doc "Decrements the active count and returns the new value."
  @spec decrement(GenServer.server()) :: integer()
  def decrement(server), do: GenServer.call(server, :decrement)

  @doc "Returns the highest value the counter has ever reached."
  @spec peak(GenServer.server()) :: integer()
  def peak(server), do: GenServer.call(server, :peak)

  @doc "Returns how many times `increment/1` has ever been called."
  @spec started(GenServer.server()) :: non_neg_integer()
  def started(server), do: GenServer.call(server, :started)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:increment, _from, %{count: count, peak: peak, started: started} = state) do
    new_count = count + 1
    new_state = %{state | count: new_count, peak: max(new_count, peak), started: started + 1}
    {:reply, new_count, new_state}
  end

  def handle_call(:decrement, _from, %{count: count} = state) do
    new_count = count - 1
    {:reply, new_count, %{state | count: new_count}}
  end

  def handle_call(:peak, _from, %{peak: peak} = state), do: {:reply, peak, state}
  def handle_call(:started, _from, %{started: started} = state), do: {:reply, started, state}
end

defmodule FailFastMap do
  @moduledoc """
  Parallel map with a concurrency limit and fail-fast semantics.

  Returns `{:ok, results}` (in input order) when every element succeeds, or
  `{:error, {index, reason}}` on the first failure — at which point every
  still-running task is killed and no queued element is started.
  """

  @doc """
  Applies `func` to each element of `collection` in parallel, running at most
  `max_concurrency` tasks at a time.

  Returns `{:ok, results}` with the return values in input order when every
  element succeeds. On the first failure (a raise or abnormal exit) it returns
  `{:error, {index, reason}}`, kills all still-running tasks, and starts no
  further queued elements. An empty collection returns `{:ok, []}`.
  """
  @spec pmap(Enumerable.t(), (term() -> term()), pos_integer()) ::
          {:ok, [term()]} | {:error, {non_neg_integer(), term()}}
  def pmap(collection, func, max_concurrency)
      when is_function(func, 1) and is_integer(max_concurrency) and max_concurrency >= 1 do
    indexed = collection |> Enum.to_list() |> Enum.with_index()

    if indexed == [] do
      {:ok, []}
    else
      parent = self()
      {seed, queue} = Enum.split(indexed, max_concurrency)

      running =
        Map.new(seed, fn {elem, idx} ->
          {ref, pid, mon} = spawn_task(parent, func, elem)
          {ref, {pid, mon, idx}}
        end)

      loop(running, queue, func, parent, %{})
    end
  end

  # Runs `func.(elem)` in a monitored (unlinked) process; all errors are caught
  # and reported back as a tagged message so the process exits `:normal`.
  defp spawn_task(parent, func, elem) do
    ref = make_ref()

    {pid, mon} =
      spawn_monitor(fn ->
        result =
          try do
            {:ok, func.(elem)}
          rescue
            e -> {:error, {e, __STACKTRACE__}}
          catch
            :exit, r -> {:error, r}
            :throw, t -> {:error, {:throw, t}}
          end

        send(parent, {ref, result})
      end)

    {ref, pid, mon}
  end

  # All tasks accounted for and none failed.
  defp loop(running, _queue, _func, _parent, results) when map_size(running) == 0 do
    {:ok, order_results(results)}
  end

  defp loop(running, queue, func, parent, results) do
    receive do
      {ref, {:ok, value}} when is_map_key(running, ref) ->
        {_pid, mon, idx} = Map.fetch!(running, ref)
        Process.demonitor(mon, [:flush])
        running = Map.delete(running, ref)
        results = Map.put(results, idx, value)

        {running, queue} =
          case queue do
            [] ->
              {running, []}

            [{elem, i} | rest] ->
              {r, pid, m} = spawn_task(parent, func, elem)
              {Map.put(running, r, {pid, m, i}), rest}
          end

        loop(running, queue, func, parent, results)

      {ref, {:error, reason}} when is_map_key(running, ref) ->
        {_pid, mon, idx} = Map.fetch!(running, ref)
        Process.demonitor(mon, [:flush])
        cancel_all(Map.delete(running, ref))
        {:error, {idx, reason}}

      {:DOWN, mon, :process, _pid, reason} ->
        case Enum.find(running, fn {_ref, {_pid, m, _idx}} -> m == mon end) do
          {ref, {_pid, _mon, idx}} ->
            cancel_all(Map.delete(running, ref))
            {:error, {idx, reason}}

          nil ->
            loop(running, queue, func, parent, results)
        end

      _other ->
        loop(running, queue, func, parent, results)
    end
  end

  # Kill every still-running task and discard any messages they may have sent.
  defp cancel_all(running) do
    Enum.each(running, fn {ref, {pid, mon, _idx}} ->
      Process.demonitor(mon, [:flush])
      Process.exit(pid, :kill)

      receive do
        {^ref, _} -> :ok
      after
        0 -> :ok
      end
    end)

    :ok
  end

  defp order_results(results) do
    results |> Map.keys() |> Enum.sort() |> Enum.map(&Map.fetch!(results, &1))
  end
end
```

Reply with `start_link` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
