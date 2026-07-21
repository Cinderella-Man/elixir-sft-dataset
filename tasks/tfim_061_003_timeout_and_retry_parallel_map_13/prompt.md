# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule ConcurrencyCounter do
  @moduledoc """
  A GenServer that tracks an active-task count and remembers the highest value
  it has ever reached (the "peak"). Intended for tests to verify that
  `RetryMap.pmap/3` never exceeds its declared concurrency limit at runtime.
  """

  use GenServer

  @doc """
  Starts the counter process.

  Accepts a `:name` option (defaulting to `#{inspect(__MODULE__)}`); any other
  options are forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {__MODULE__, rest}
        {name, rest} -> {name, rest}
      end

    GenServer.start_link(__MODULE__, %{count: 0, peak: 0}, [{:name, name} | server_opts])
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

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:increment, _from, %{count: count, peak: peak} = state) do
    new_count = count + 1
    {:reply, new_count, %{state | count: new_count, peak: max(new_count, peak)}}
  end

  def handle_call(:decrement, _from, %{count: count} = state) do
    new_count = count - 1
    {:reply, new_count, %{state | count: new_count}}
  end

  def handle_call(:peak, _from, %{peak: peak} = state), do: {:reply, peak, state}
end

defmodule RetryMap do
  @moduledoc """
  Concurrency-limited parallel map with per-attempt timeouts and bounded retries.

  Each element yields a tagged result: `{:ok, value}` on success,
  `{:error, :timeout}` after exhausting timed-out attempts, or a tagged error
  such as `{:error, {:exception, reason}}` for a permanent (non-retried) crash.
  """

  @doc """
  Applies `func` to each element of `collection` in parallel and returns a list
  of tagged results in the **same order** as the input.

  At most `:max_concurrency` tasks are alive at once. Each attempt is given
  `:timeout` milliseconds; a timed-out attempt is killed and retried up to
  `:max_attempts` total attempts before yielding `{:error, :timeout}`. A raised
  exception (or abnormal exit) is a permanent failure and is not retried.

  ## Options

    * `:max_concurrency` — maximum tasks alive simultaneously (default `5`)
    * `:timeout` — per-attempt timeout in milliseconds (default `5000`)
    * `:max_attempts` — maximum attempts per element (default `1`)
  """
  @spec pmap(Enumerable.t(), (term() -> term()), keyword()) :: [{:ok, term()} | {:error, term()}]
  def pmap(collection, func, opts) when is_function(func, 1) and is_list(opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 5)
    timeout = Keyword.get(opts, :timeout, 5000)
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    unless is_integer(max_concurrency) and max_concurrency >= 1,
      do: raise(ArgumentError, ":max_concurrency must be a positive integer")

    unless is_integer(timeout) and timeout >= 0,
      do: raise(ArgumentError, ":timeout must be a non-negative integer")

    unless is_integer(max_attempts) and max_attempts >= 1,
      do: raise(ArgumentError, ":max_attempts must be a positive integer")

    indexed =
      collection
      |> Enum.to_list()
      |> Enum.with_index()
      |> Enum.map(fn {elem, idx} -> {elem, idx, max_attempts} end)

    total = length(indexed)

    if total == 0 do
      []
    else
      cfg = %{func: func, timeout: timeout}
      {seed, queue} = Enum.split(indexed, max_concurrency)

      running =
        Enum.reduce(seed, %{}, fn {elem, idx, attempts}, acc ->
          {ref, entry} = start_attempt(self(), func, elem, idx, attempts, timeout)
          Map.put(acc, ref, entry)
        end)

      results = loop(running, queue, cfg, %{})
      Enum.map(0..(total - 1), &Map.fetch!(results, &1))
    end
  end

  # Spawns one attempt for `elem`, arms a per-attempt timeout, and returns the
  # bookkeeping entry keyed by a fresh ref.
  defp start_attempt(parent, func, elem, idx, attempts_left, timeout) do
    ref = make_ref()

    {pid, mon} =
      spawn_monitor(fn ->
        result =
          try do
            {:ok, func.(elem)}
          rescue
            e -> {:error, {:exception, e}}
          catch
            :exit, r -> {:error, {:exit, r}}
            :throw, t -> {:error, {:throw, t}}
          end

        send(parent, {ref, result})
      end)

    timer = Process.send_after(parent, {:timeout, ref}, timeout)
    {ref, {pid, mon, idx, elem, attempts_left, timer}}
  end

  defp loop(running, queue, _cfg, results) when map_size(running) == 0 and queue == [] do
    results
  end

  defp loop(running, queue, cfg, results) do
    receive do
      {ref, {:ok, value}} when is_map_key(running, ref) ->
        {_pid, mon, idx, _elem, _al, timer} = Map.fetch!(running, ref)
        cleanup(mon, timer)
        running = Map.delete(running, ref)
        results = Map.put(results, idx, {:ok, value})
        {running, queue} = fill(running, queue, cfg)
        loop(running, queue, cfg, results)

      {ref, {:error, reason}} when is_map_key(running, ref) ->
        {_pid, mon, idx, _elem, _al, timer} = Map.fetch!(running, ref)
        cleanup(mon, timer)
        running = Map.delete(running, ref)
        results = Map.put(results, idx, {:error, reason})
        {running, queue} = fill(running, queue, cfg)
        loop(running, queue, cfg, results)

      {:timeout, ref} when is_map_key(running, ref) ->
        {pid, mon, idx, elem, attempts_left, timer} = Map.fetch!(running, ref)
        cleanup(mon, timer)
        Process.exit(pid, :kill)
        drain(ref)
        running = Map.delete(running, ref)
        remaining = attempts_left - 1

        if remaining > 0 do
          {r, entry} = start_attempt(self(), cfg.func, elem, idx, remaining, cfg.timeout)
          loop(Map.put(running, r, entry), queue, cfg, results)
        else
          results = Map.put(results, idx, {:error, :timeout})
          {running, queue} = fill(running, queue, cfg)
          loop(running, queue, cfg, results)
        end

      {:DOWN, mon, :process, _pid, reason} ->
        case Enum.find(running, fn {_r, {_p, m, _i, _e, _a, _t}} -> m == mon end) do
          {ref, {_pid, _mon, idx, _elem, _al, timer}} ->
            Process.cancel_timer(timer)
            drain(ref)
            running = Map.delete(running, ref)
            results = Map.put(results, idx, {:error, {:down, reason}})
            {running, queue} = fill(running, queue, cfg)
            loop(running, queue, cfg, results)

          nil ->
            loop(running, queue, cfg, results)
        end

      _other ->
        loop(running, queue, cfg, results)
    end
  end

  defp fill(running, [], _cfg), do: {running, []}

  defp fill(running, [{elem, idx, attempts} | rest], cfg) do
    {ref, entry} = start_attempt(self(), cfg.func, elem, idx, attempts, cfg.timeout)
    {Map.put(running, ref, entry), rest}
  end

  defp cleanup(mon, timer) do
    Process.demonitor(mon, [:flush])
    Process.cancel_timer(timer)
    :ok
  end

  defp drain(ref) do
    receive do
      {^ref, _} -> :ok
    after
      0 -> :ok
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule RetryMapTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Basic correctness
  # -------------------------------------------------------

  test "empty collection returns []" do
    assert [] = RetryMap.pmap([], fn x -> x end, max_concurrency: 3)
  end

  test "all success returns tagged results in order" do
    results = RetryMap.pmap(1..5, fn x -> x * 10 end, max_concurrency: 2, timeout: 1000)
    assert results == [{:ok, 10}, {:ok, 20}, {:ok, 30}, {:ok, 40}, {:ok, 50}]
  end

  test "order preserved when tasks finish out of order" do
    results =
      RetryMap.pmap(
        1..6,
        fn x ->
          Process.sleep((7 - x) * 20)
          x
        end,
        max_concurrency: 6,
        timeout: 1000
      )

    assert results == Enum.map(1..6, &{:ok, &1})
  end

  # -------------------------------------------------------
  # Timeout + retry
  # -------------------------------------------------------

  test "an element that times out once but succeeds on retry returns {:ok, value}" do
    {:ok, agent} = Agent.start_link(fn -> %{} end)

    func = fn x ->
      n =
        Agent.get_and_update(agent, fn m ->
          c = Map.get(m, x, 0) + 1
          {c, Map.put(m, x, c)}
        end)

      if n == 1, do: Process.sleep(300)
      x * 2
    end

    results = RetryMap.pmap([1, 2, 3], func, max_concurrency: 3, timeout: 100, max_attempts: 3)
    assert results == [{:ok, 2}, {:ok, 4}, {:ok, 6}]
  end

  test "an element that always times out returns {:error, :timeout} after exhausting attempts" do
    results =
      RetryMap.pmap(
        [1],
        fn _ ->
          Process.sleep(500)
          :never
        end,
        max_concurrency: 1,
        timeout: 80,
        max_attempts: 2
      )

    assert results == [{:error, :timeout}]
  end

  # -------------------------------------------------------
  # Permanent failure (no retry)
  # -------------------------------------------------------

  test "an exception is permanent and is NOT retried" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    results =
      RetryMap.pmap(
        [1],
        fn _ ->
          Agent.update(agent, &(&1 + 1))
          raise "boom"
        end,
        max_concurrency: 1,
        timeout: 1000,
        max_attempts: 3
      )

    assert match?([{:error, {:exception, _}}], results)
    assert Agent.get(agent, & &1) == 1
  end

  test "a crash in one element does not affect the others" do
    results =
      RetryMap.pmap(
        [1, 2, 3],
        fn
          2 -> raise "only me"
          x -> x * 10
        end,
        max_concurrency: 3,
        timeout: 1000,
        max_attempts: 2
      )

    assert Enum.at(results, 0) == {:ok, 10}
    assert match?({:error, {:exception, _}}, Enum.at(results, 1))
    assert Enum.at(results, 2) == {:ok, 30}
  end

  # -------------------------------------------------------
  # Concurrency limit enforcement
  # -------------------------------------------------------

  test "never exceeds max_concurrency simultaneous tasks" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    RetryMap.pmap(
      1..8,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        Process.sleep(60)
        ConcurrencyCounter.decrement(counter)
      end,
      max_concurrency: 3,
      timeout: 1000,
      max_attempts: 1
    )

    assert ConcurrencyCounter.peak(counter) <= 3
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
      ConcurrencyCounter.decrement(c)
      assert ConcurrencyCounter.peak(c) == 2
    end
  end

  test "a timed-out attempt is really killed and produces no late side effect" do
    parent = self()

    results =
      RetryMap.pmap(
        [1],
        fn x ->
          Process.sleep(300)
          send(parent, {:late, x})
          x
        end,
        max_concurrency: 1,
        timeout: 60,
        max_attempts: 1
      )

    assert results == [{:error, :timeout}]
    refute_receive {:late, 1}, 500
  end

  test "a timeout in one element does not affect the others" do
    results =
      RetryMap.pmap(
        [1, 2, 3],
        fn
          2 ->
            Process.sleep(400)
            :never

          x ->
            x * 10
        end,
        max_concurrency: 3,
        timeout: 80,
        max_attempts: 1
      )

    assert results == [{:ok, 10}, {:error, :timeout}, {:ok, 30}]
  end

  test "max_attempts defaults to 1 so a timed-out element is attempted exactly once" do
    # TODO
  end

  test "a queued element does not start while a timed-out element is retrying" do
    parent = self()

    spawn(fn ->
      out =
        RetryMap.pmap(
          [1, 2],
          fn
            1 ->
              Process.sleep(1000)
              :never

            2 ->
              send(parent, :second_started)
              20
          end,
          max_concurrency: 1,
          timeout: 100,
          max_attempts: 2
        )

      send(parent, {:pmap_done, out})
    end)

    refute_receive :second_started, 150
    assert_receive :second_started, 1000
    assert_receive {:pmap_done, [{:error, :timeout}, {:ok, 20}]}, 1000
  end

  test "max_concurrency defaults to 5 when the option is omitted" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    RetryMap.pmap(
      1..12,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        Process.sleep(60)
        ConcurrencyCounter.decrement(counter)
      end,
      timeout: 2000
    )

    peak = ConcurrencyCounter.peak(counter)
    assert peak <= 5
    assert peak > 1
  end

  test "ConcurrencyCounter honours the :name option and returns new values" do
    {:ok, _pid} = ConcurrencyCounter.start_link(name: :retry_map_named_counter)

    assert ConcurrencyCounter.increment(:retry_map_named_counter) == 1
    assert ConcurrencyCounter.increment(:retry_map_named_counter) == 2
    assert ConcurrencyCounter.decrement(:retry_map_named_counter) == 1
    assert ConcurrencyCounter.peak(:retry_map_named_counter) == 2
  end

  # -------------------------------------------------------
  # Default per-attempt timeout (5000 ms)
  # -------------------------------------------------------

  test "the omitted :timeout tolerates work far shorter than the 5000 ms default" do
    results =
      RetryMap.pmap(
        [1],
        fn x ->
          Process.sleep(300)
          x * 3
        end,
        max_concurrency: 1,
        max_attempts: 1
      )

    assert results == [{:ok, 3}]
  end

  test "the omitted :timeout is finite and fires at the 5000 ms default" do
    parent = self()

    spawn(fn ->
      out =
        RetryMap.pmap(
          [1],
          fn _ ->
            Process.sleep(9_000)
            :never
          end,
          max_concurrency: 1,
          max_attempts: 1
        )

      send(parent, {:default_timeout_done, out})
    end)

    # A default shorter than 5000 ms would yield a terminal result within 3 s.
    refute_receive {:default_timeout_done, _}, 3_000
    # A default that never fires would yield nothing, since the work runs for 9 s.
    assert_receive {:default_timeout_done, [{:error, :timeout}]}, 4_000
  end
end
```
