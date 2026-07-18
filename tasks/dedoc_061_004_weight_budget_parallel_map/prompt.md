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
defmodule WeightMeter do
  use GenServer

  def start_link(opts \\ []) do
    {name, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {__MODULE__, rest}
        {name, rest} -> {name, rest}
      end

    GenServer.start_link(__MODULE__, %{current: 0, peak: 0}, [{:name, name} | server_opts])
  end

  def add(server, weight), do: GenServer.call(server, {:add, weight})

  def sub(server, weight), do: GenServer.call(server, {:sub, weight})

  def peak(server), do: GenServer.call(server, :peak)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:add, weight}, _from, %{current: current, peak: peak} = state) do
    new_current = current + weight
    {:reply, new_current, %{state | current: new_current, peak: max(new_current, peak)}}
  end

  def handle_call({:sub, weight}, _from, %{current: current} = state) do
    new_current = current - weight
    {:reply, new_current, %{state | current: new_current}}
  end

  def handle_call(:peak, _from, %{peak: peak} = state), do: {:reply, peak, state}
end

defmodule WeightedMap do
  def pmap(collection, func, weight_fun, budget)
      when is_function(func, 1) and is_function(weight_fun, 1) and
             is_integer(budget) and budget >= 1 do
    indexed =
      collection
      |> Enum.to_list()
      |> Enum.with_index()
      |> Enum.map(fn {elem, idx} ->
        w = weight_fun.(elem)

        unless is_integer(w) and w >= 1 do
          raise ArgumentError, "weight_fun must return a positive integer, got: #{inspect(w)}"
        end

        {elem, idx, w}
      end)

    total = length(indexed)

    if total == 0 do
      []
    else
      state = %{
        parent: self(),
        func: func,
        budget: budget,
        weight: 0,
        running: %{},
        queue: indexed,
        results: %{}
      }

      results = run(state)
      Enum.map(0..(total - 1), &Map.fetch!(results, &1))
    end
  end

  # Admit as many queued elements as the budget allows, then wait for one to
  # finish; repeat until everything is done.
  defp run(state) do
    state = admit(state)

    if map_size(state.running) == 0 and state.queue == [] do
      state.results
    else
      state |> collect_one() |> run()
    end
  end

  # Head-of-line admission: keep starting the queue head while it fits, or while
  # it is an oversize element and nothing else is running.
  defp admit(%{queue: []} = state), do: state

  defp admit(%{queue: [{elem, idx, w} | rest]} = state) do
    %{running: running, weight: weight, budget: budget} = state

    cond do
      weight + w <= budget ->
        {ref, entry} = spawn_task(state.parent, state.func, elem, idx, w)
        admit(%{state | queue: rest, running: Map.put(running, ref, entry), weight: weight + w})

      weight == 0 and w > budget ->
        {ref, entry} = spawn_task(state.parent, state.func, elem, idx, w)
        admit(%{state | queue: rest, running: Map.put(running, ref, entry), weight: weight + w})

      true ->
        state
    end
  end

  defp spawn_task(parent, func, elem, idx, w) do
    ref = make_ref()

    {_pid, mon} =
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

    {ref, {mon, idx, w}}
  end

  defp collect_one(%{running: running} = state) do
    receive do
      {ref, result} when is_map_key(running, ref) ->
        {mon, idx, w} = Map.fetch!(running, ref)
        Process.demonitor(mon, [:flush])

        outcome =
          case result do
            {:ok, value} -> value
            {:error, reason} -> {:error, reason}
          end

        %{
          state
          | running: Map.delete(running, ref),
            weight: state.weight - w,
            results: Map.put(state.results, idx, outcome)
        }

      {:DOWN, mon, :process, _pid, reason} ->
        case Enum.find(running, fn {_ref, {m, _idx, _w}} -> m == mon end) do
          {ref, {_mon, idx, w}} ->
            %{
              state
              | running: Map.delete(running, ref),
                weight: state.weight - w,
                results: Map.put(state.results, idx, {:error, reason})
            }

          nil ->
            collect_one(state)
        end

      _other ->
        collect_one(state)
    end
  end
end
```
