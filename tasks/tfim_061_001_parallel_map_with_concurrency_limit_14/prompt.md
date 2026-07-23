# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

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

  Scheduling is implemented with `Task.async`/`Task.yield_many` over a
  sliding window of at most `max_concurrency` tasks. `Task.async` links the
  task to the caller, so exits are trapped for the duration of the run (and
  restored afterwards): a crashing task then surfaces as a harmless
  `{:exit, reason}` yield result instead of killing the caller.
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
      # `Task.async` links each task to this process; trap exits so an
      # abnormally exiting task delivers a message instead of killing us,
      # then restore the flag and drain those messages before returning.
      was_trapping? = Process.flag(:trap_exit, true)

      try do
        {seed, queue} = Enum.split(indexed, max_concurrency)

        # running: %{%Task{} => original_index}
        running = Map.new(seed, fn {elem, idx} -> {start_task(func, elem), idx} end)

        pids = Map.new(Map.keys(running), &{&1.pid, true})
        {raw, pids} = collect(running, queue, func, _results = %{}, pids)

        # Reassemble in original order.
        result = Enum.map(0..(total - 1), fn i -> Map.fetch!(raw, i) end)
        Process.flag(:trap_exit, was_trapping?)
        # Drain ONLY our own tasks' exits: a trapping caller may hold
        # unrelated {:EXIT, ...} mail of its own that pmap must not eat.
        flush_exit_messages(pids)
        result
      after
        Process.flag(:trap_exit, was_trapping?)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp start_task(func, elem), do: Task.async(fn -> func.(elem) end)

  # Base case: nothing running and nothing queued.
  defp collect(running, [] = _queue, _func, results, pids) when map_size(running) == 0,
    do: {results, pids}

  # The as-they-finish loop: harvest whatever `Task.yield_many/2` reports in
  # this tick — a normal reply (`{:ok, value}`) or a crash (`{:exit, reason}`,
  # covering raises, abnormal exits, throws and external kills alike) — then
  # refill the freed slots from the queue and go again.
  defp collect(running, queue, func, results, pids) do
    finished =
      running
      |> Map.keys()
      |> Task.yield_many(20)
      |> Enum.filter(fn {_task, res} -> res != nil end)

    case finished do
      [] ->
        collect(running, queue, func, results, pids)

      finished ->
        finished
        |> Enum.reduce({running, queue, results, pids}, fn {task, res}, {run, q, acc, ps} ->
          idx = Map.fetch!(run, task)

          outcome =
            case res do
              {:ok, value} -> value
              {:exit, reason} -> {:error, reason}
            end

          run = Map.delete(run, task)
          acc = Map.put(acc, idx, outcome)

          case q do
            [] ->
              {run, [], acc, ps}

            [{elem, next_idx} | rest] ->
              refill = start_task(func, elem)
              {Map.put(run, refill, next_idx), rest, acc, Map.put(ps, refill.pid, true)}
          end
        end)
        |> then(fn {run, q, acc, ps} -> collect(run, q, func, acc, ps) end)
    end
  end

  # Trapped exits from finished/crashed tasks land in our mailbox; drain
  # exactly THOSE (matched by task pid) so pmap leaves the caller's mailbox
  # as it found it — including any unrelated {:EXIT, ...} a trapping caller
  # was already holding.
  defp flush_exit_messages(pids) do
    receive do
      {:EXIT, pid, _reason} when is_map_key(pids, pid) -> flush_exit_messages(pids)
    after
      0 -> :ok
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
    {:ok, counter} = ConcurrencyCounter.start_link([])

    ParallelMap.pmap(
      1..5,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        slow(:ok, 30)
        ConcurrencyCounter.decrement(counter)
      end,
      1
    )

    assert ConcurrencyCounter.peak(counter) == 1
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

  # An element whose function exits abnormally (rather than raising) still
  # yields {:error, reason} in that element's slot, and its neighbours keep
  # running to completion.
  test "an exiting function returns {:error, reason} for that item only" do
    results =
      ParallelMap.pmap(
        1..5,
        fn
          3 -> exit(:no_thanks)
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

  # A task that dies without any chance to report — a brutal kill of its own
  # process — is still reported as {:error, reason} for that element, and the
  # other in-flight tasks are neither cancelled nor corrupted.
  test "a brutally killed task returns {:error, reason} without cancelling others" do
    results =
      ParallelMap.pmap(
        1..4,
        fn
          2 -> Process.exit(self(), :kill)
          x -> slow(x * 3, 40)
        end,
        4
      )

    assert Enum.at(results, 0) == 3
    assert match?({:error, _}, Enum.at(results, 1))
    assert Enum.at(results, 2) == 9
    assert Enum.at(results, 3) == 12
  end

  # An abnormal exit frees its concurrency slot: the still-queued elements are
  # all spawned and every element gets a result, in input order.
  test "queued items still run after earlier tasks exit abnormally" do
    input = Enum.to_list(1..8)

    results =
      ParallelMap.pmap(
        input,
        fn
          x when x in [1, 2] -> exit({:bad, x})
          x -> slow(x * 100, 20)
        end,
        2
      )

    assert length(results) == 8
    assert match?({:error, _}, Enum.at(results, 0))
    assert match?({:error, _}, Enum.at(results, 1))
    assert Enum.drop(results, 2) == Enum.map(3..8, &(&1 * 100))
  end

  # A mixture of failure modes across a single call: each failing element gets
  # its own {:error, reason} and successes are unaffected.
  test "raise, exit and kill failures coexist in one call" do
    results =
      ParallelMap.pmap(
        [:raise, :ok_a, :exit, :ok_b, :kill],
        fn
          :raise -> raise "nope"
          :exit -> exit(:bye)
          :kill -> Process.exit(self(), :kill)
          other -> slow(other, 30)
        end,
        3
      )

    assert match?({:error, _}, Enum.at(results, 0))
    assert Enum.at(results, 1) == :ok_a
    assert match?({:error, _}, Enum.at(results, 2))
    assert Enum.at(results, 3) == :ok_b
    assert match?({:error, _}, Enum.at(results, 4))
  end

  # -------------------------------------------------------
  # ConcurrencyCounter unit tests
  # -------------------------------------------------------

  describe "ConcurrencyCounter" do
    test "starts at zero and tracks peak" do
      # TODO
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

  test "pmap preserves a trapping caller's own unrelated :EXIT mail" do
    was_trapping? = Process.flag(:trap_exit, true)

    try do
      victim = spawn_link(fn -> exit(:boom) end)

      # Wait until OUR trapped exit is genuinely queued — pmap must not eat it.
      wait = fn wait ->
        {:messages, msgs} = Process.info(self(), :messages)

        unless Enum.any?(msgs, &match?({:EXIT, ^victim, :boom}, &1)) do
          Process.sleep(5)
          wait.(wait)
        end
      end

      wait.(wait)

      # A crashing element forces pmap's own trapped task exits into the
      # mailbox alongside ours; its flush may only remove its own.
      results =
        ParallelMap.pmap(
          [1, :crash, 3],
          fn
            :crash -> raise "kaboom"
            x -> x * 2
          end,
          2
        )

      assert length(results) == 3

      assert_receive {:EXIT, ^victim, :boom}
      refute_receive {:EXIT, _, _}, 50
    after
      Process.flag(:trap_exit, was_trapping?)
    end
  end
end
```
