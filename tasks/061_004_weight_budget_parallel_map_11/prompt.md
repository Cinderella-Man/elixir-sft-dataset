# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `run` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

**Summary:** Implement Elixir module `WeightedMap` — parallel map over a collection where the concurrency limit is a **weight budget**, not a task count. Ship a helper GenServer `WeightMeter` in the same file. Single file, complete implementation.

**Public API — `WeightedMap`**
- `WeightedMap.pmap(collection, func, weight_fun, budget)` — the only public function.
- `weight_fun` maps an element to a **positive integer** weight; `budget` is a positive integer.
- Applies `func` to each element in parallel such that the **sum of the weights of all in-flight tasks never exceeds `budget`**.
- Results are returned in the **same order** as the input collection, regardless of completion order.

**Admission / scheduling**
- Admit elements in **strict input order (head-of-line blocking)**: only the element at the head of the queue is eligible to start.
- The head starts only once the currently running total weight plus its own weight is `<= budget`.
- If the head does not fit, nothing behind it may start — a lighter element further back must **not** jump ahead of a blocked heavier head.
- Oversized-element special case: if a single element's weight is **greater than `budget`**, it would otherwise never run — allow it to run **alone**, only when nothing else is currently running. While it runs, no other element may start.

**Validation**
- `pmap/4` validates weights: if `weight_fun` returns anything other than a positive integer for some element (e.g. `0`), it raises an `ArgumentError`.

**Crash handling**
- If `func` raises, or the spawned task exits abnormally, that element's result is `{:error, reason}`.
- A crash must not affect or cancel other in-flight tasks.
- The crashed element's weight must be released back to the budget.

**Helper GenServer — `WeightMeter`** (same file)
- `WeightMeter.start_link(opts)` — starts the process, accepts `:name`.
- `WeightMeter.add(server, weight)` — adds `weight` to the in-flight total, returns the new total.
- `WeightMeter.sub(server, weight)` — subtracts `weight` from the in-flight total, returns the new total.
- `WeightMeter.peak(server)` — returns the highest in-flight total the meter has ever reached.
- Intended for use in tests to verify the weight budget is actually respected at runtime; the `pmap` implementation itself does not need to use it.

**Constraints**
- OTP and standard library only — no external dependencies.
- Do not use `Task.async_stream`.
- Implement the weight-aware admission and scheduling logic yourself using `spawn_monitor`.
- Deliver everything in a single file.

## The module with `run` missing

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

  defp run(state) do
    # TODO
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

Reply with `run` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
