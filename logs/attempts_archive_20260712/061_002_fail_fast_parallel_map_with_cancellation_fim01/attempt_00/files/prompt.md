# Fill in the middle: implement `FailFastMap.loop/5`

The module below implements a parallel `pmap` with a concurrency limit and
fail-fast semantics. Everything is written for you **except** the private
`loop/5` function, whose body has been replaced with `# TODO`.

Implement the private `loop/5` function — the receive-loop scheduler that drives
the running tasks to completion (or to the first failure). It is called with five
arguments: `loop(running, queue, func, parent, results)`, where:

- `running` is a map of `ref => {pid, mon, idx}` for every task currently alive,
  keyed by the unique `ref` used in that task's result message.
- `queue` is the list of `{elem, index}` pairs that have **not yet** been started
  (the work still waiting for a free concurrency slot).
- `func` is the one-arity function being applied to each element.
- `parent` is the pid that spawned tasks send their results to (the caller of
  `pmap/3`).
- `results` is a map of `index => value` accumulating the successful return
  values, later ordered by `order_results/1`.

Behavior:

1. **Termination.** When there are no more running tasks (`map_size(running) == 0`),
   everything has completed successfully: return `{:ok, order_results(results)}`.

2. **Otherwise**, wait for a message with `receive` and handle these cases:
   - `{ref, {:ok, value}}` where `ref` is a key in `running` — a task finished
     successfully. Demonitor its monitor with `Process.demonitor(mon, [:flush])`,
     remove `ref` from `running`, and record `value` under that task's `idx` in
     `results`. Then, if `queue` is non-empty, pop its head `{elem, i}`, spawn a
     new task for it with `spawn_task(parent, func, elem)`, and add the returned
     `{ref, {pid, mon, i}}` entry to `running` (leaving the rest of the queue).
     If `queue` is empty, start nothing new. Recurse with the updated state.
   - `{ref, {:error, reason}}` where `ref` is a key in `running` — a task reported
     a failure. Demonitor its monitor, then `cancel_all/1` on the remaining running
     tasks (after removing `ref`) and return `{:error, {idx, reason}}` using the
     failing task's `idx`.
   - `{:DOWN, mon, :process, _pid, reason}` — a monitored task went down without
     sending a result. Find the running entry whose monitor is `mon`; if one is
     found, `cancel_all/1` the remaining tasks (after removing that entry) and
     return `{:error, {idx, reason}}` for its `idx`. If no entry matches (a stale
     `:DOWN` after we already handled/flushed it), ignore it and keep looping.
   - Any other message — ignore it and keep looping.

```elixir
defmodule ConcurrencyCounter do
  @moduledoc """
  A GenServer that tracks an active-task count, the highest value it has ever
  reached (`peak`), and the total number of times it was incremented
  (`started`). Intended for tests to verify that `FailFastMap.pmap/3` respects
  its concurrency limit and cancels queued work after a failure.
  """

  use GenServer

  @doc """
  Starts the counter process.

  Accepts a `:name` option; any other options are forwarded to
  `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {__MODULE__, rest}
        {name, rest} -> {name, rest}
      end

    init_state = %{count: 0, peak: 0, started: 0}
    GenServer.start_link(__MODULE__, init_state, [{:name, name} | server_opts])
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
    # TODO
  end

  defp loop(running, queue, func, parent, results) do
    # TODO
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