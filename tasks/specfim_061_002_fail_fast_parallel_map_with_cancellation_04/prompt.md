# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`decrement/1` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `decrement/1`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `decrement/1` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
