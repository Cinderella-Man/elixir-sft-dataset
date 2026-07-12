# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `WeightedMap` that applies a function to a collection in
parallel, but where the concurrency limit is a **weight budget** rather than a simple task
count.

I need one public function:
- `WeightedMap.pmap(collection, func, weight_fun, budget)` where `weight_fun` maps an
  element to a **positive integer** weight and `budget` is a positive integer. It applies
  `func` to each element in parallel such that the **sum of the weights of all in-flight
  tasks never exceeds `budget`**. Results are returned in the **same order** as the input
  collection, regardless of completion order.

Admission rules:
- Admit elements in input order (head-of-line). A queued element may only start once the
  currently running total weight plus its own weight is `<= budget`.
- Special case: if a single element's weight is **greater than `budget`**, it would
  otherwise never run — so allow it to run **alone** (only when nothing else is currently
  running). While it runs, no other element may start.

Task crash handling: if `func` raises or the spawned task exits abnormally for a given
element, that element's result should be `{:error, reason}` — this must not affect or cancel
other in-flight tasks, and the element's weight must be released back to the budget.

You will also need to write a helper GenServer called `WeightMeter` in the same file. It must
expose:
- `WeightMeter.start_link(opts)` — starts the process, accepts `:name`
- `WeightMeter.add(server, weight)` — adds `weight` to the in-flight total, returns the new total
- `WeightMeter.sub(server, weight)` — subtracts `weight` from the in-flight total, returns the new total
- `WeightMeter.peak(server)` — returns the highest in-flight total the meter has ever reached

`WeightMeter` is intended for use in tests to verify that the weight budget is actually
respected at runtime; your `pmap` implementation itself does not need to use it.

Give me the complete implementation in a single file. Use only OTP and the standard library —
no external dependencies. Do not use `Task.async_stream`; implement the weight-aware
admission and scheduling logic yourself using `spawn_monitor`.

## Additional interface contract

- `pmap/4` validates weights: if `weight_fun` returns anything other than a positive
  integer for some element (e.g. `0`), it raises an `ArgumentError`.

## The buggy module

```elixir
defmodule WeightMeter do
  @moduledoc """
  A GenServer that tracks a running total of in-flight weight and remembers the
  highest total it has ever reached. Intended for tests to verify that
  `WeightedMap.pmap/4` never exceeds its declared weight budget at runtime.
  """

  use GenServer

  @doc """
  Starts the meter. Accepts `:name` to register the process; any other options
  are passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {__MODULE__, rest}
        {name, rest} -> {name, rest}
      end

    GenServer.start_link(__MODULE__, %{current: 0, peak: 0}, [{:name, name} | server_opts])
  end

  @doc "Adds `weight` to the in-flight total and returns the new total."
  @spec add(GenServer.server(), integer()) :: integer()
  def add(server, weight), do: GenServer.call(server, {:add, weight})

  @doc "Subtracts `weight` from the in-flight total and returns the new total."
  @spec sub(GenServer.server(), integer()) :: integer()
  def sub(server, weight), do: GenServer.call(server, {:sub, weight})

  @doc "Returns the highest in-flight total the meter has ever reached."
  @spec peak(GenServer.server()) :: integer()
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
  @moduledoc """
  Parallel map whose concurrency is bounded by a weight *budget*: the sum of the
  weights of all in-flight tasks never exceeds `budget`. Elements are admitted in
  input order; an element heavier than the whole budget is allowed to run alone.

  Results are returned in input order; a raised exception or abnormal task exit
  yields `{:error, reason}` for that element and releases its weight, leaving all
  other in-flight tasks untouched.
  """

  @doc """
  Applies `func` to every element of `collection` in parallel, keeping the sum of
  the weights (from `weight_fun`) of all in-flight tasks within `budget`.

  Elements are admitted in input order. An element whose weight exceeds `budget`
  runs alone. Results are returned in input order; a crash for an element yields
  `{:error, reason}` for that element only.
  """
  @spec pmap(
          Enumerable.t(),
          (term() -> term()),
          (term() -> pos_integer()),
          pos_integer()
        ) :: [term()]
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

    if total == 1 do
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

## Failing test report

```
1 of 11 test(s) failed:

  * test empty collection returns []
      key 0 not found in:
      
          %{}
```
