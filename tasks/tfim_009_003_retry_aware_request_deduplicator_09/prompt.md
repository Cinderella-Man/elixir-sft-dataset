# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule RetryDedup do
  @moduledoc """
  A GenServer that deduplicates concurrent requests per key and automatically
  retries failed executions with exponential backoff.

  Callers that arrive while an execution (or its retry sequence) is in flight
  join the wait list and receive the eventual result — whether success after
  retries, or the final error when the retry budget is exhausted.

  ## Retry semantics

  On failure (raise or `{:error, _}`), the GenServer waits
  `min(base_delay_ms * 2^attempt, max_delay_ms)` then re-invokes `func` in a
  fresh Task. Callers are only unblocked once either:
    - `func` succeeds, or
    - all retries are exhausted.

  ## Example

      {:ok, pid} = RetryDedup.start_link([])
      counter = :counters.new(1, [:atomics])

      result = RetryDedup.execute(pid, :flaky, fn ->
        n = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)
        if n < 2, do: {:error, :not_yet}, else: {:ok, :finally}
      end, max_retries: 5)

      result  #=> {:ok, :finally}
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    server_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, %{}, server_opts)
  end

  @doc """
  Runs `func` under `key`, coalescing concurrent duplicate calls into one execution
  and retrying per `opts`. Returns the function's result.
  """
  @spec execute(GenServer.server(), term(), (-> term()), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute(server, key, func, opts \\ []) when is_function(func, 0) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    base_delay_ms = Keyword.get(opts, :base_delay_ms, 100)
    max_delay_ms = Keyword.get(opts, :max_delay_ms, 5_000)

    retry_config = %{
      max_retries: max_retries,
      base_delay_ms: base_delay_ms,
      max_delay_ms: max_delay_ms
    }

    GenServer.call(server, {:execute, key, func, retry_config}, :infinity)
  end

  @spec status(GenServer.server(), term()) ::
          :idle | {:retrying, pos_integer(), non_neg_integer()}
  def status(server, key) do
    GenServer.call(server, {:status, key})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  # State shape:
  #   %{
  #     key => %{
  #       callers:      [GenServer.from()],
  #       func:         (() -> term()),
  #       retry_config: %{max_retries: _, base_delay_ms: _, max_delay_ms: _},
  #       attempt:      non_neg_integer(),  # 0 = initial, 1 = first retry, ...
  #       status:       :running | :waiting_retry
  #     }
  #   }

  @impl GenServer
  def init(_opts) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:execute, key, func, retry_config}, from, state) do
    case Map.fetch(state, key) do
      :error ->
        spawn_attempt(key, func)

        entry = %{
          callers: [from],
          func: func,
          retry_config: retry_config,
          attempt: 0,
          status: :running
        }

        {:noreply, Map.put(state, key, entry)}

      {:ok, entry} ->
        updated = %{entry | callers: entry.callers ++ [from]}
        {:noreply, Map.put(state, key, updated)}
    end
  end

  def handle_call({:status, key}, _from, state) do
    reply =
      case Map.fetch(state, key) do
        {:ok, %{attempt: attempt, retry_config: %{max_retries: max}}} when attempt > 0 ->
          {:retrying, attempt, max}

        {:ok, _} ->
          :idle

        :error ->
          :idle
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_info({:task_result, key, result}, state) do
    case Map.fetch(state, key) do
      {:ok, entry} ->
        handle_attempt_result(key, entry, result, state)

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:retry_now, key}, state) do
    case Map.fetch(state, key) do
      {:ok, %{func: func} = entry} ->
        spawn_attempt(key, func)
        {:noreply, Map.put(state, key, %{entry | status: :running})}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp handle_attempt_result(key, entry, result, state) do
    case result do
      {:ok, _} = success ->
        reply_all(entry.callers, success)
        {:noreply, Map.delete(state, key)}

      {:error, _} = error ->
        if entry.attempt < entry.retry_config.max_retries do
          next_attempt = entry.attempt + 1
          delay = compute_delay(next_attempt, entry.retry_config)
          Process.send_after(self(), {:retry_now, key}, delay)

          updated = %{entry | attempt: next_attempt, status: :waiting_retry}
          {:noreply, Map.put(state, key, updated)}
        else
          reply_all(entry.callers, error)
          {:noreply, Map.delete(state, key)}
        end
    end
  end

  defp spawn_attempt(key, func) do
    parent = self()

    Task.start(fn ->
      result =
        try do
          case func.() do
            {:ok, _} = ok -> ok
            {:error, _} = err -> err
            other -> {:ok, other}
          end
        rescue
          exception -> {:error, {:exception, exception}}
        end

      send(parent, {:task_result, key, result})
    end)
  end

  defp compute_delay(attempt, %{base_delay_ms: base, max_delay_ms: max_d}) do
    # attempt is 1-based here (first retry = attempt 1)
    raw = base * Integer.pow(2, attempt - 1)
    min(raw, max_d)
  end

  defp reply_all(callers, result) do
    Enum.each(callers, &GenServer.reply(&1, result))
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule RetryDedupTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = RetryDedup.start_link([])
    %{rd: pid}
  end

  # -------------------------------------------------------
  # Basic execution (no retries needed)
  # -------------------------------------------------------

  test "executes the function and returns the result", %{rd: rd} do
    assert {:ok, 42} = RetryDedup.execute(rd, "k", fn -> {:ok, 42} end)
  end

  test "wraps plain return values in an ok tuple", %{rd: rd} do
    assert {:ok, "hello"} = RetryDedup.execute(rd, "k", fn -> "hello" end)
  end

  test "passes through {:error, reason} as-is when retries exhausted", %{rd: rd} do
    assert {:error, :permanent} =
             RetryDedup.execute(rd, "k", fn -> {:error, :permanent} end, max_retries: 0)
  end

  # -------------------------------------------------------
  # Deduplication — callers share the same execution
  # -------------------------------------------------------

  test "concurrent calls with the same key share execution", %{rd: rd} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(counter, &(&1 + 1))
      Process.sleep(200)
      {:ok, :result}
    end

    tasks =
      for _ <- 1..10 do
        Task.async(fn -> RetryDedup.execute(rd, "same", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, &(&1 == {:ok, :result}))
    assert Agent.get(counter, & &1) == 1
  end

  test "different keys execute independently", %{rd: rd} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(counter, &(&1 + 1))
      Process.sleep(100)
      {:ok, :done}
    end

    tasks =
      for i <- 1..5 do
        Task.async(fn -> RetryDedup.execute(rd, "key:#{i}", func) end)
      end

    results = Task.await_many(tasks, 5_000)
    assert Enum.all?(results, &(&1 == {:ok, :done}))
    assert Agent.get(counter, & &1) == 5
  end

  # -------------------------------------------------------
  # Retry behaviour
  # -------------------------------------------------------

  test "retries on failure and eventually succeeds", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(attempt_counter, fn n -> {n, n + 1} end)

      if n < 2 do
        {:error, :not_yet}
      else
        {:ok, :finally}
      end
    end

    result =
      RetryDedup.execute(rd, "flaky", func,
        max_retries: 5,
        base_delay_ms: 10
      )

    assert result == {:ok, :finally}
    # initial + 2 retries = 3 total calls
    assert Agent.get(attempt_counter, & &1) == 3
  end

  test "returns last error when all retries exhausted", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(attempt_counter, &(&1 + 1))
      {:error, :always_fails}
    end

    result =
      RetryDedup.execute(rd, "doomed", func,
        max_retries: 3,
        base_delay_ms: 10
      )

    assert result == {:error, :always_fails}
    # initial + 3 retries = 4 total calls
    assert Agent.get(attempt_counter, & &1) == 4
  end

  test "retries on exception and wraps as {:error, {:exception, _}}", %{rd: rd} do
    # TODO
  end

  # -------------------------------------------------------
  # Callers joining during retries
  # -------------------------------------------------------

  test "callers arriving during retry share the eventual result", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(attempt_counter, fn n -> {n, n + 1} end)

      if n < 2 do
        {:error, :not_yet}
      else
        Process.sleep(100)
        {:ok, :shared_result}
      end
    end

    # First caller triggers execution
    task1 =
      Task.async(fn ->
        RetryDedup.execute(rd, "join", func,
          max_retries: 5,
          base_delay_ms: 50
        )
      end)

    # Wait for first attempt + some retry delay, then add a second caller
    Process.sleep(120)

    task2 =
      Task.async(fn ->
        RetryDedup.execute(rd, "join", func,
          max_retries: 5,
          base_delay_ms: 50
        )
      end)

    [r1, r2] = Task.await_many([task1, task2], 10_000)

    # Both get the same result
    assert r1 == {:ok, :shared_result}
    assert r2 == {:ok, :shared_result}
  end

  # -------------------------------------------------------
  # Key clearing after completion
  # -------------------------------------------------------

  test "key is cleared after success, allowing fresh execution", %{rd: rd} do
    assert {:ok, 1} = RetryDedup.execute(rd, "k", fn -> {:ok, 1} end)
    assert {:ok, 2} = RetryDedup.execute(rd, "k", fn -> {:ok, 2} end)
  end

  test "key is cleared after final failure, allowing fresh execution", %{rd: rd} do
    assert {:error, :fail} =
             RetryDedup.execute(rd, "k", fn -> {:error, :fail} end, max_retries: 0)

    assert {:ok, :ok_now} = RetryDedup.execute(rd, "k", fn -> {:ok, :ok_now} end)
  end

  # -------------------------------------------------------
  # Status
  # -------------------------------------------------------

  test "status returns :idle for unknown key", %{rd: rd} do
    assert RetryDedup.status(rd, "nothing") == :idle
  end

  test "status returns :idle during first attempt", %{rd: rd} do
    task =
      Task.async(fn ->
        RetryDedup.execute(rd, "running", fn ->
          Process.sleep(300)
          {:ok, :done}
        end)
      end)

    Process.sleep(50)
    # During initial execution (attempt 0), status is :idle (no retries yet)
    assert RetryDedup.status(rd, "running") == :idle

    Task.await(task, 5_000)
  end

  test "status reflects retry state", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    task =
      Task.async(fn ->
        RetryDedup.execute(
          rd,
          "retrying",
          fn ->
            n = Agent.get_and_update(attempt_counter, fn n -> {n, n + 1} end)

            if n < 3 do
              {:error, :not_yet}
            else
              Process.sleep(100)
              {:ok, :done}
            end
          end,
          max_retries: 5,
          base_delay_ms: 100
        )
      end)

    # Wait for first failure + start of retry delay
    Process.sleep(150)
    status = RetryDedup.status(rd, "retrying")
    assert match?({:retrying, _, 5}, status)

    Task.await(task, 10_000)

    # After completion, status is idle
    assert RetryDedup.status(rd, "retrying") == :idle
  end

  # -------------------------------------------------------
  # Exponential backoff timing
  # -------------------------------------------------------

  test "retries take progressively longer", %{rd: rd} do
    {:ok, timestamps} = Agent.start_link(fn -> [] end)

    func = fn ->
      Agent.update(timestamps, fn ts -> ts ++ [System.monotonic_time(:millisecond)] end)
      {:error, :nope}
    end

    RetryDedup.execute(rd, "timing", func,
      max_retries: 3,
      base_delay_ms: 50,
      max_delay_ms: 1_000
    )

    ts = Agent.get(timestamps, & &1)
    # Should have 4 timestamps: initial + 3 retries
    assert length(ts) == 4

    delays =
      ts
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)

    # Each delay should be roughly: 50, 100, 200 (exponential)
    # Allow some slack for scheduling
    [d1, d2, d3] = delays
    assert d1 >= 30
    assert d2 >= d1
    assert d3 >= d2
  end

  test "retry delay never exceeds :max_delay_ms", %{rd: rd} do
    {:ok, timestamps} = Agent.start_link(fn -> [] end)

    func = fn ->
      Agent.update(timestamps, fn ts -> ts ++ [System.monotonic_time(:millisecond)] end)
      {:error, :nope}
    end

    assert {:error, :nope} =
             RetryDedup.execute(rd, "capped", func,
               max_retries: 3,
               base_delay_ms: 500,
               max_delay_ms: 40
             )

    ts = Agent.get(timestamps, & &1)
    assert length(ts) == 4

    delays =
      ts
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)

    # min(500 * 2^(attempt - 1), 40) == 40 for every retry here; without the cap
    # the gaps would be 500, 1000 and 2000 ms.
    assert Enum.all?(delays, &(&1 < 300))
  end

  # -------------------------------------------------------
  # Default options
  # -------------------------------------------------------

  test "defaults to 3 retries with a 100 ms base delay", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(attempt_counter, &(&1 + 1))
      {:error, :always_fails}
    end

    {elapsed_us, result} =
      :timer.tc(fn -> RetryDedup.execute(rd, "defaulted", func) end)

    assert result == {:error, :always_fails}
    # default max_retries of 3: initial + 3 retries = 4 total calls
    assert Agent.get(attempt_counter, & &1) == 4

    # default base_delay_ms of 100 gives gaps of 100 + 200 + 400 = 700 ms,
    # well under the 5000 ms default cap
    elapsed_ms = div(elapsed_us, 1_000)
    assert elapsed_ms >= 650
    assert elapsed_ms < 3_000
  end

  # -------------------------------------------------------
  # GenServer responsiveness
  # -------------------------------------------------------

  test "GenServer is not blocked during retries", %{rd: rd} do
    slow_task =
      Task.async(fn ->
        RetryDedup.execute(rd, "slow_retry", fn -> {:error, :fail} end,
          max_retries: 5,
          base_delay_ms: 200
        )
      end)

    Process.sleep(50)

    {elapsed, result} =
      :timer.tc(fn ->
        RetryDedup.execute(rd, "fast", fn -> {:ok, :fast} end)
      end)

    assert result == {:ok, :fast}
    assert elapsed < 200_000

    Task.await(slow_task, 10_000)
  end

  # -------------------------------------------------------
  # Error broadcasting with retries
  # -------------------------------------------------------

  test "all callers receive the final error after retries exhausted", %{rd: rd} do
    func = fn ->
      Process.sleep(50)
      {:error, :persistent_failure}
    end

    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          RetryDedup.execute(rd, "err_broadcast", func,
            max_retries: 1,
            base_delay_ms: 10
          )
        end)
      end

    results = Task.await_many(tasks, 5_000)
    assert Enum.all?(results, &(&1 == {:error, :persistent_failure}))
  end

  test "registers under the :name option and is reachable by that name" do
    name = :retry_dedup_name_promise_srv
    {:ok, _} = RetryDedup.start_link(name: name)

    assert {:ok, 7} = RetryDedup.execute(name, "k", fn -> {:ok, 7} end)
  end

  test "status reports 1-based attempt number at the first retry", %{rd: rd} do
    test = self()

    func = fn ->
      send(test, {:running, self()})

      receive do
        :fail -> {:error, :again}
        :succeed -> {:ok, :done}
      end
    end

    t =
      Task.async(fn ->
        RetryDedup.execute(rd, "attempt_num", func, max_retries: 4, base_delay_ms: 1)
      end)

    # Initial attempt (attempt 0) — status is still :idle here.
    assert_receive {:running, p1}, 2_000
    send(p1, :fail)

    # First retry is attempt 1, not attempt 0.
    assert_receive {:running, p2}, 2_000
    assert RetryDedup.status(rd, "attempt_num") == {:retrying, 1, 4}
    send(p2, :fail)

    # Second retry is attempt 2.
    assert_receive {:running, p3}, 2_000
    assert RetryDedup.status(rd, "attempt_num") == {:retrying, 2, 4}
    send(p3, :succeed)

    assert {:ok, :done} = Task.await(t, 5_000)
  end

  test "a joining caller during retries does not spawn an extra execution", %{rd: rd} do
    test = self()

    func = fn ->
      send(test, {:running, self()})

      receive do
        :fail -> {:error, :again}
        :succeed -> {:ok, :done}
      end
    end

    t1 =
      Task.async(fn ->
        RetryDedup.execute(rd, "no_restart", func, max_retries: 5, base_delay_ms: 1)
      end)

    assert_receive {:running, p1}, 2_000
    send(p1, :fail)

    # Second caller joins while the retry sequence is in flight.
    assert_receive {:running, p2}, 2_000

    t2 =
      Task.async(fn ->
        RetryDedup.execute(rd, "no_restart", func, max_retries: 5, base_delay_ms: 1)
      end)

    send(p2, :fail)
    assert_receive {:running, p3}, 2_000
    send(p3, :fail)
    assert_receive {:running, p4}, 2_000
    send(p4, :succeed)

    assert {:ok, :done} = Task.await(t1, 5_000)
    assert {:ok, :done} = Task.await(t2, 5_000)

    # A restart would have produced a fifth invocation of func.
    refute_receive {:running, _}, 300
  end
end
```
