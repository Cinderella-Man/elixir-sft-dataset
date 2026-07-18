# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule ConcurrencyCounter do
  use GenServer

  def start_link(opts \\ []) do
    {name, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {__MODULE__, rest}
        {name, rest} -> {name, rest}
      end

    init_state = %{count: 0, peak: 0, started: 0}
    GenServer.start_link(__MODULE__, init_state, [{:name, name} | server_opts])
  end

  def increment(server), do: GenServer.call(server, :increment)

  def decrement(server), do: GenServer.call(server, :decrement)

  def peak(server), do: GenServer.call(server, :peak)

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
