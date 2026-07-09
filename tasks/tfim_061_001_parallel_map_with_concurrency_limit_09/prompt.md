# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule ConcurrencyCounter do
  @moduledoc """
  A GenServer that tracks an active-task count and remembers the highest
  value it has ever reached (the "peak"). Intended for use in tests to
  verify that `ParallelMap.pmap/3` never exceeds its declared concurrency
  limit at runtime.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Starts the counter. Accepts `:name` in `opts`."
  def start_link(opts \\ []) do
    {name, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {__MODULE__, rest}
        {name, rest} -> {name, rest}
      end

    GenServer.start_link(__MODULE__, %{count: 0, peak: 0}, [{:name, name} | server_opts])
  end

  @doc "Increments the active count by 1. Returns the new value."
  def increment(server), do: GenServer.call(server, :increment)

  @doc "Decrements the active count by 1. Returns the new value."
  def decrement(server), do: GenServer.call(server, :decrement)

  @doc "Returns the highest value the counter has ever reached."
  def peak(server), do: GenServer.call(server, :peak)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:increment, _from, %{count: count, peak: peak} = state) do
    new_count = count + 1
    new_state = %{state | count: new_count, peak: max(new_count, peak)}
    {:reply, new_count, new_state}
  end

  def handle_call(:decrement, _from, %{count: count} = state) do
    new_count = count - 1
    {:reply, new_count, %{state | count: new_count}}
  end

  def handle_call(:peak, _from, %{peak: peak} = state) do
    {:reply, peak, state}
  end
end

defmodule ParallelMap do
  @moduledoc """
  Applies a function to every element of a collection in parallel while
  keeping the number of concurrently running tasks at or below
  `max_concurrency`.

  Results are always returned in the same order as the input. If the
  function raises or the spawned process exits abnormally, the corresponding
  result is `{:error, reason}`; all other in-flight tasks continue
  unaffected.

  Scheduling is implemented with `spawn_monitor` rather than `Task.async`
  so that task crashes never propagate as exit signals to the caller —
  only a `:DOWN` monitor message is delivered.
  """

  @doc """
  Maps `func` over `collection` in parallel, with at most `max_concurrency`
  tasks alive at any one time.

  ## Examples

      iex> ParallelMap.pmap(1..5, fn x -> x * 2 end, 2)
      [2, 4, 6, 8, 10]

      iex> ParallelMap.pmap([1, :boom, 3], fn
      ...>   :boom -> raise "oops"
      ...>   x    -> x * 10
      ...> end, 2)
      [10, {:error, _}, 30]
  """
  @spec pmap(Enumerable.t(), (term() -> term()), pos_integer()) :: [term()]
  def pmap(collection, func, max_concurrency)
      when is_function(func, 1) and is_integer(max_concurrency) and max_concurrency >= 1 do
    indexed = collection |> Enum.to_list() |> Enum.with_index()
    total = length(indexed)

    if total == 0 do
      []
    else
      parent = self()
      {seed, queue} = Enum.split(indexed, max_concurrency)

      # running: %{our_ref => {monitor_ref, original_index}}
      #
      # We use our own `make_ref()` as the primary key because it is the
      # value embedded in the result message that the spawned process sends
      # back.  The monitor ref is kept alongside so we can demonitor cleanly
      # after receiving the result.
      running =
        Map.new(seed, fn {elem, idx} ->
          {our_ref, mon_ref} = spawn_task(parent, func, elem)
          {our_ref, {mon_ref, idx}}
        end)

      raw = collect(running, queue, func, parent, _results = %{})

      # Reassemble in original order.
      Enum.map(0..(total - 1), fn i -> Map.fetch!(raw, i) end)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Spawns a monitored (but NOT linked) process that runs `func.(elem)`.
  #
  # All exceptions and exits are caught inside the spawned process and
  # converted into a tagged result message sent to `parent`.  This means
  # the process always exits with reason `:normal`, so the `:DOWN` message
  # we will eventually receive is harmless and can simply be flushed.
  #
  # Returns `{our_ref, monitor_ref}`.
  defp spawn_task(parent, func, elem) do
    our_ref = make_ref()

    {_pid, mon_ref} =
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

        send(parent, {our_ref, result})
      end)

    {our_ref, mon_ref}
  end

  # Base case: nothing running and nothing queued.
  defp collect(running, _queue = [], _func, _parent, results)
       when map_size(running) == 0,
       do: results

  defp collect(running, queue, func, parent, results) do
    {finished_ref, finished_idx, outcome} = await_one(running)

    new_results = Map.put(results, finished_idx, outcome)
    new_running = Map.delete(running, finished_ref)

    # Fill the freed slot immediately.
    {new_running, new_queue} =
      case queue do
        [] ->
          {new_running, []}

        [{elem, idx} | rest] ->
          {our_ref, mon_ref} = spawn_task(parent, func, elem)
          {Map.put(new_running, our_ref, {mon_ref, idx}), rest}
      end

    collect(new_running, new_queue, func, parent, new_results)
  end

  # Blocks until a message arrives from one of our running tasks.
  #
  # Two cases:
  #   1. `{our_ref, result}` — the task completed (normally or via our
  #      try/catch wrapper) and reported its outcome.  We demonitor with
  #      `:flush` to discard the subsequent `:normal` DOWN message.
  #
  #   2. `{:DOWN, mon_ref, …, reason}` — the process was killed externally
  #      (e.g. a brutal `Process.exit(pid, :kill)`) before it could send a
  #      result message.  We locate the entry by monitor ref and wrap the
  #      reason in `{:error, …}`.
  #
  # Any unrelated message is left to fall through and we recurse.
  defp await_one(running) do
    receive do
      {our_ref, result} when is_map_key(running, our_ref) ->
        {mon_ref, idx} = Map.fetch!(running, our_ref)
        Process.demonitor(mon_ref, [:flush])

        outcome =
          case result do
            {:ok, value} -> value
            {:error, reason} -> {:error, reason}
          end

        {our_ref, idx, outcome}

      {:DOWN, mon_ref, :process, _pid, reason} ->
        # Unexpected external kill — locate the task by its monitor ref.
        case Enum.find(running, fn {_ref, {mon, _idx}} -> mon == mon_ref end) do
          {our_ref, {_mon, idx}} -> {our_ref, idx, {:error, reason}}
          nil -> await_one(running)
        end

      _other ->
        await_one(running)
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule ParallelMapTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  # Sleeps for `ms` then returns the value — used to keep tasks alive long
  # enough for the concurrency counter to observe them.
  defp slow(value, ms) do
    Process.sleep(ms)
    value
  end

  # -------------------------------------------------------
  # Basic correctness
  # -------------------------------------------------------

  test "maps over an empty collection" do
    assert [] = ParallelMap.pmap([], fn x -> x * 2 end, 3)
  end

  test "returns results in original order" do
    input = Enum.to_list(1..20)

    results = ParallelMap.pmap(input, fn x -> x * 10 end, 4)

    assert results == Enum.map(input, &(&1 * 10))
  end

  test "works when collection is smaller than max_concurrency" do
    results = ParallelMap.pmap([1, 2], fn x -> x + 1 end, 10)
    assert results == [2, 3]
  end

  test "works with max_concurrency of 1 (sequential)" do
    results = ParallelMap.pmap([3, 1, 2], fn x -> x * x end, 1)
    assert results == [9, 1, 4]
  end

  test "works with max_concurrency equal to collection size" do
    results = ParallelMap.pmap([1, 2, 3], fn x -> x + 100 end, 3)
    assert results == [101, 102, 103]
  end

  # -------------------------------------------------------
  # Concurrency limit enforcement
  # -------------------------------------------------------

  test "never exceeds max_concurrency=3 simultaneous tasks" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    ParallelMap.pmap(
      1..10,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        slow(:ok, 60)
        ConcurrencyCounter.decrement(counter)
      end,
      3
    )

    assert ConcurrencyCounter.peak(counter) <= 3
  end

  test "actually runs tasks in parallel (peak > 1 with concurrency > 1)" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    ParallelMap.pmap(
      1..6,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        slow(:ok, 80)
        ConcurrencyCounter.decrement(counter)
      end,
      3
    )

    # With 6 items and max 3, we should reach at least 2 simultaneously
    assert ConcurrencyCounter.peak(counter) >= 2
  end

  test "max_concurrency=1 never exceeds 1 simultaneous task" do
    # TODO
  end

  # -------------------------------------------------------
  # Crash / error handling
  # -------------------------------------------------------

  test "a crashing function returns {:error, reason} for that item" do
    results =
      ParallelMap.pmap(
        [1, 2, 3],
        fn
          2 -> raise "boom"
          x -> x * 10
        end,
        3
      )

    assert Enum.at(results, 0) == 10
    assert match?({:error, _}, Enum.at(results, 1))
    assert Enum.at(results, 2) == 30
  end

  test "crash in one task does not cancel other tasks" do
    results =
      ParallelMap.pmap(
        1..5,
        fn
          3 -> raise "only me"
          x -> slow(x * 2, 40)
        end,
        5
      )

    assert Enum.at(results, 0) == 2
    assert Enum.at(results, 1) == 4
    assert match?({:error, _}, Enum.at(results, 2))
    assert Enum.at(results, 3) == 8
    assert Enum.at(results, 4) == 10
  end

  test "all items crash — returns all error tuples" do
    results = ParallelMap.pmap([1, 2, 3], fn _ -> raise "always" end, 2)

    assert length(results) == 3
    assert Enum.all?(results, &match?({:error, _}, &1))
  end

  test "result order is preserved even when tasks finish out of order" do
    # Items with larger index sleep longer, so they finish last
    input = Enum.to_list(1..6)

    results =
      ParallelMap.pmap(
        input,
        fn x ->
          # item 1 sleeps longest
          Process.sleep((7 - x) * 20)
          x
        end,
        6
      )

    assert results == input
  end

  # -------------------------------------------------------
  # ConcurrencyCounter unit tests
  # -------------------------------------------------------

  describe "ConcurrencyCounter" do
    test "starts at zero and tracks peak" do
      {:ok, c} = ConcurrencyCounter.start_link([])

      assert ConcurrencyCounter.peak(c) == 0

      ConcurrencyCounter.increment(c)
      ConcurrencyCounter.increment(c)
      ConcurrencyCounter.increment(c)
      ConcurrencyCounter.decrement(c)

      assert ConcurrencyCounter.peak(c) == 3
    end

    test "increment returns the new count" do
      {:ok, c} = ConcurrencyCounter.start_link([])
      assert ConcurrencyCounter.increment(c) == 1
      assert ConcurrencyCounter.increment(c) == 2
    end

    test "decrement returns the new count" do
      {:ok, c} = ConcurrencyCounter.start_link([])
      ConcurrencyCounter.increment(c)
      ConcurrencyCounter.increment(c)
      assert ConcurrencyCounter.decrement(c) == 1
      assert ConcurrencyCounter.decrement(c) == 0
    end
  end
end
```
