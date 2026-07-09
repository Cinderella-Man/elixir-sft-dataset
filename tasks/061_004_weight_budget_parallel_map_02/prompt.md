Implement the private `admit/1` function.

`admit/1` performs head-of-line admission: given the scheduler `state` (a map with
`:queue` — a list of `{elem, idx, weight}` tuples still waiting to start, `:running`
— a map of monitor refs to running-task entries, `:weight` — the current sum of
in-flight weights, `:budget`, and the fields needed by `spawn_task/5`), it starts as
many queued elements as the weight budget allows and returns the updated state.

It should recurse over the queue, always considering the head element
`{elem, idx, w}`:

- If the current in-flight `weight` plus this element's weight `w` is `<= budget`,
  start it: call `spawn_task(state.parent, state.func, elem, idx, w)` to get
  `{ref, entry}`, then recurse with the head removed from `:queue`, the task added to
  `:running` under `ref`, and `:weight` increased by `w`.
- Otherwise, if nothing is currently running (`weight == 0`) and this element is
  oversize (`w > budget`), it must still be allowed to run alone: start it exactly as
  above and recurse.
- Otherwise the head does not fit right now — stop and return the state unchanged so
  the scheduler can wait for a running task to finish.

When the queue is empty, return the state unchanged (base case).

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
  defp admit(state) do
    # TODO
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