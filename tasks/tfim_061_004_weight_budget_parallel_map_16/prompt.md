# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule WeightedMapTest do
  use ExUnit.Case, async: false

  defp slow(value, ms) do
    Process.sleep(ms)
    value
  end

  # -------------------------------------------------------
  # Basic correctness
  # -------------------------------------------------------

  test "empty collection returns []" do
    assert [] = WeightedMap.pmap([], fn x -> x end, fn _ -> 1 end, 5)
  end

  test "returns results in original order" do
    input = Enum.to_list(1..10)
    results = WeightedMap.pmap(input, fn x -> x * 10 end, fn _ -> 1 end, 3)
    assert results == Enum.map(input, &(&1 * 10))
  end

  test "weighted elements are mapped in order" do
    input = [3, 5, 2, 4, 6, 1]
    results = WeightedMap.pmap(input, fn x -> x * 10 end, & &1, 8)
    assert results == Enum.map(input, &(&1 * 10))
  end

  test "order preserved when tasks finish out of order" do
    results =
      WeightedMap.pmap(
        1..6,
        fn x ->
          Process.sleep((7 - x) * 20)
          x
        end,
        fn _ -> 1 end,
        6
      )

    assert results == Enum.to_list(1..6)
  end

  # -------------------------------------------------------
  # Weight budget enforcement
  # -------------------------------------------------------

  test "never exceeds the weight budget" do
    {:ok, meter} = WeightMeter.start_link([])

    input = [3, 5, 2, 4, 6, 1, 3, 2]

    WeightedMap.pmap(
      input,
      fn x ->
        WeightMeter.add(meter, x)
        slow(:ok, 40)
        WeightMeter.sub(meter, x)
      end,
      & &1,
      8
    )

    assert WeightMeter.peak(meter) <= 8
  end

  test "a task heavier than the budget runs alone" do
    {:ok, meter} = WeightMeter.start_link([])

    # weight 10 > budget 4: it must run by itself, so the peak is exactly 10.
    WeightedMap.pmap(
      [10, 1],
      fn x ->
        WeightMeter.add(meter, x)
        slow(:ok, 40)
        WeightMeter.sub(meter, x)
      end,
      & &1,
      4
    )

    assert WeightMeter.peak(meter) == 10
  end

  test "runs several small tasks in parallel under the budget" do
    {:ok, meter} = WeightMeter.start_link([])

    WeightedMap.pmap(
      List.duplicate(1, 6),
      fn x ->
        WeightMeter.add(meter, x)
        slow(:ok, 80)
        WeightMeter.sub(meter, x)
      end,
      & &1,
      3
    )

    assert WeightMeter.peak(meter) >= 2
    assert WeightMeter.peak(meter) <= 3
  end

  # -------------------------------------------------------
  # Crash handling
  # -------------------------------------------------------

  test "a crashing function returns {:error, reason} for that element only" do
    results =
      WeightedMap.pmap(
        [1, 2, 3],
        fn
          2 -> raise "boom"
          x -> x * 10
        end,
        fn _ -> 1 end,
        3
      )

    assert Enum.at(results, 0) == 10
    assert match?({:error, _}, Enum.at(results, 1))
    assert Enum.at(results, 2) == 30
  end

  test "a crash releases weight so remaining work still proceeds" do
    results =
      WeightedMap.pmap(
        [5, 5, 5],
        fn
          x -> if x == 5, do: x
        end,
        & &1,
        5
      )

    # All weights equal budget, so they run one at a time; each returns its value.
    assert results == [5, 5, 5]
  end

  test "invalid weight raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1, 2], fn x -> x end, fn _ -> 0 end, 5)
    end
  end

  # -------------------------------------------------------
  # WeightMeter unit tests
  # -------------------------------------------------------

  describe "WeightMeter" do
    test "tracks running total and peak" do
      {:ok, m} = WeightMeter.start_link([])
      assert WeightMeter.peak(m) == 0
      assert WeightMeter.add(m, 3) == 3
      assert WeightMeter.add(m, 4) == 7
      assert WeightMeter.sub(m, 5) == 2
      assert WeightMeter.peak(m) == 7
    end
  end

  test "weight of a raising element is released so later queued work still runs" do
    results =
      WeightedMap.pmap(
        [4, 1, 1],
        fn
          4 -> raise "boom"
          x -> x * 100
        end,
        & &1,
        4
      )

    assert match?({:error, _}, Enum.at(results, 0))
    assert Enum.drop(results, 1) == [100, 100]
  end

  test "an oversize element waits until every running element has finished" do
    parent = self()

    spawn_link(fn ->
      results =
        WeightedMap.pmap(
          [1, 10],
          fn x ->
            send(parent, {:started, x, self()})

            receive do
              :go -> x
            end
          end,
          & &1,
          4
        )

      send(parent, {:results, results})
    end)

    assert_receive {:started, 1, p1}, 1_000
    refute_receive {:started, 10, _}, 200
    send(p1, :go)
    assert_receive {:started, 10, p10}, 1_000
    send(p10, :go)
    assert_receive {:results, [1, 10]}, 1_000
  end

  test "a light element does not jump ahead of a blocked heavier queue head" do
    parent = self()

    spawn_link(fn ->
      results =
        WeightedMap.pmap(
          [2, 3, 1],
          fn x ->
            send(parent, {:started, x, self()})

            receive do
              :go -> x * 10
            end
          end,
          & &1,
          3
        )

      send(parent, {:results, results})
    end)

    assert_receive {:started, 2, p2}, 1_000
    refute_receive {:started, 1, _}, 200
    send(p2, :go)
    assert_receive {:started, 3, p3}, 1_000
    send(p3, :go)
    assert_receive {:started, 1, p1}, 1_000
    send(p1, :go)
    assert_receive {:results, [20, 30, 10]}, 1_000
  end

  test "a task killed abnormally yields an error tuple and leaves the others intact" do
    # TODO
  end

  test "float, negative and non-numeric weights all raise ArgumentError" do
    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1], fn x -> x end, fn _ -> 1.5 end, 5)
    end

    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1], fn x -> x end, fn _ -> -2 end, 5)
    end

    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1], fn x -> x end, fn _ -> :heavy end, 5)
    end

    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1, 2], fn x -> x end, fn x -> x - 1 end, 5)
    end
  end

  test "WeightMeter can be reached through a registered :name" do
    {:ok, pid} = WeightMeter.start_link(name: :audit_weight_meter)

    assert Process.whereis(:audit_weight_meter) == pid
    assert WeightMeter.add(:audit_weight_meter, 4) == 4
    assert WeightMeter.add(:audit_weight_meter, 3) == 7
    assert WeightMeter.sub(:audit_weight_meter, 7) == 0
    assert WeightMeter.peak(:audit_weight_meter) == 7
  end

  test "a raising element frees its weight for a queued element while a sibling runs" do
    parent = self()

    spawn_link(fn ->
      results =
        WeightedMap.pmap(
          [{:hold, 1}, {:boom, 3}, {:queued, 3}],
          fn
            {:boom, _} ->
              raise "boom"

            {tag, _} ->
              send(parent, {:started, tag, self()})

              receive do
                :go -> tag
              end
          end,
          fn {_tag, weight} -> weight end,
          4
        )

      send(parent, {:results, results})
    end)

    assert_receive {:started, :hold, hold_pid}, 1_000

    # The raising element's weight of 3 goes back to the budget at once, so the
    # queued element of weight 3 is admitted while the first element still runs.
    assert_receive {:started, :queued, queued_pid}, 1_000

    send(hold_pid, :go)
    send(queued_pid, :go)
    assert_receive {:results, [:hold, {:error, _}, :queued]}, 1_000
  end

  test "an abnormal exit at full budget frees the budget for the blocked queue head" do
    # Every weight equals the budget, so element 3 can only start if the weight
    # of the killed element 2 was returned to the budget.
    results =
      WeightedMap.pmap(
        [1, 2, 3],
        fn
          2 -> Process.exit(self(), :kill)
          x -> x * 10
        end,
        fn _ -> 3 end,
        3
      )

    assert Enum.at(results, 0) == 10
    assert Enum.at(results, 1) == {:error, :killed}
    assert Enum.at(results, 2) == 30
  end
end
```
