# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule FailFastMapTest do
  use ExUnit.Case, async: false

  defp slow(value, ms) do
    Process.sleep(ms)
    value
  end

  # -------------------------------------------------------
  # Success path
  # -------------------------------------------------------

  test "empty collection returns {:ok, []}" do
    assert {:ok, []} = FailFastMap.pmap([], fn x -> x end, 3)
  end

  test "all-success returns {:ok, results} in original order" do
    input = Enum.to_list(1..20)
    assert {:ok, results} = FailFastMap.pmap(input, fn x -> x * 10 end, 4)
    assert results == Enum.map(input, &(&1 * 10))
  end

  test "order preserved even when tasks finish out of order" do
    assert {:ok, results} =
             FailFastMap.pmap(1..6, fn x -> Process.sleep((7 - x) * 20); x end, 6)

    assert results == Enum.to_list(1..6)
  end

  test "works sequentially with max_concurrency of 1" do
    assert {:ok, [9, 1, 4]} = FailFastMap.pmap([3, 1, 2], fn x -> x * x end, 1)
  end

  # -------------------------------------------------------
  # Fail-fast path
  # -------------------------------------------------------

  test "first failure returns {:error, {index, reason}}" do
    assert {:error, {5, _reason}} =
             FailFastMap.pmap(1..6, fn
               6 -> raise "boom"
               x -> x * 2
             end, 2)
  end

  test "failure at index 0 is reported with index 0" do
    assert {:error, {0, _reason}} =
             FailFastMap.pmap([:bad, 2, 3], fn
               :bad -> raise "nope"
               x -> x
             end, 3)
  end

  test "queued work is cancelled after a failure (not all elements started)" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    result =
      FailFastMap.pmap(1..30, fn
        1 ->
          raise "boom"

        _x ->
          ConcurrencyCounter.increment(counter)
          slow(:ok, 200)
          ConcurrencyCounter.decrement(counter)
      end, 3)

    assert {:error, {0, _}} = result
    # Only the initial window (minus the failing element) could have started.
    assert ConcurrencyCounter.started(counter) < 30
  end

  # -------------------------------------------------------
  # Concurrency limit enforcement
  # -------------------------------------------------------

  test "never exceeds max_concurrency simultaneous tasks" do
    # TODO
  end

  test "actually runs tasks in parallel" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    assert {:ok, _} =
             FailFastMap.pmap(1..6, fn _x ->
               ConcurrencyCounter.increment(counter)
               slow(:ok, 80)
               ConcurrencyCounter.decrement(counter)
             end, 3)

    assert ConcurrencyCounter.peak(counter) >= 2
  end

  # -------------------------------------------------------
  # ConcurrencyCounter unit tests
  # -------------------------------------------------------

  describe "ConcurrencyCounter" do
    test "tracks peak and started" do
      {:ok, c} = ConcurrencyCounter.start_link([])
      assert ConcurrencyCounter.increment(c) == 1
      assert ConcurrencyCounter.increment(c) == 2
      assert ConcurrencyCounter.decrement(c) == 1
      assert ConcurrencyCounter.peak(c) == 2
      assert ConcurrencyCounter.started(c) == 2
    end
  end
end
```
