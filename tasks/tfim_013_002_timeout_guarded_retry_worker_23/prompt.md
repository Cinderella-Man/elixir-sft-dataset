# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule TimeoutRetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff, jitter,
  and per-attempt timeouts enforced via Task.yield/Task.shutdown.

  Each attempt runs inside a supervised, unlinked Task so that an abnormal
  exit in the user function cannot bring down the worker; such an exit is
  surfaced as a retryable `{:task_crashed, reason}` failure.

  The per-attempt timeout is enforced INSIDE the attempt task by a nested
  `Task.yield/2` + `Task.shutdown/2` pair, and outcomes come back as plain
  task messages routed through per-execution records keyed by task ref —
  the server itself never blocks, so no caller's slow attempt or backoff
  wait delays another caller's reply.
  """

  use GenServer
  import Bitwise

  # --- Public API ---

  @doc "Starts the worker. Accepts `:name`, `:clock`, and `:random` options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Runs `func`, retrying on failure until the timeout in `opts`. Returns the result."
  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()} | {:error, :max_retries_exceeded, any()}
  def execute(server, func, opts \\ []) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    random = Keyword.get(opts, :random, fn max -> :rand.uniform(max) - 1 end)
    {:ok, supervisor} = Task.Supervisor.start_link()
    {:ok, %{clock: clock, random: random, supervisor: supervisor, tasks: %{}}}
  end

  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    # Attempt 0 launches from handle_info exactly like every retry — the
    # contract pins "spawned from within the GenServer's handle_info".
    send(self(), {:retry, func, 0, opts, from})
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry, func, attempt, opts, from}, state) do
    state = launch_attempt(func, attempt, opts, from, state)
    {:noreply, state}
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    # Defensive: a stray result for an execution we no longer track is ignored.
    Process.demonitor(ref, [:flush])

    case Map.pop(state.tasks, ref) do
      {nil, _} ->
        {:noreply, state}

      {%{from: from, func: func, attempt: attempt, opts: opts}, new_tasks} ->
        state = %{state | tasks: new_tasks}
        handle_task_result(result, func, attempt, opts, from, state)
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.tasks, ref) do
      {nil, _} ->
        {:noreply, state}

      {%{from: from, func: func, attempt: attempt, opts: opts}, new_tasks} ->
        state = %{state | tasks: new_tasks}
        handle_task_result({:error, {:task_crashed, reason}}, func, attempt, opts, from, state)
    end
  end

  # --- Private Helpers ---

  defp launch_attempt(func, attempt, opts, from, state) do
    timeout = Keyword.get(opts, :attempt_timeout_ms, 5_000)

    # The timeout runs INSIDE the wrapper task, which owns the inner task
    # and may therefore yield to and shut it down; the server never blocks.
    # A crash in `func` kills the linked wrapper with the same reason, so
    # it surfaces at the server as this task's :DOWN — the
    # `{:task_crashed, reason}` path.
    task =
      Task.Supervisor.async_nolink(state.supervisor, fn ->
        inner = Task.async(fn -> func.() end)

        case Task.yield(inner, timeout) do
          {:ok, result} ->
            result

          nil ->
            _ = Task.shutdown(inner, :brutal_kill)
            {:error, :timeout}
        end
      end)

    record = %{from: from, func: func, attempt: attempt, opts: opts}
    %{state | tasks: Map.put(state.tasks, task.ref, record)}
  end

  defp handle_task_result_sync(result, func, attempt, opts, from, state) do
    max_retries = Keyword.get(opts, :max_retries, 3)

    case result do
      {:ok, value} ->
        GenServer.reply(from, {:ok, value})
        {:ok, state}

      {:error, reason} ->
        if attempt >= max_retries do
          GenServer.reply(from, {:error, :max_retries_exceeded, reason})
          {:exhausted, state}
        else
          schedule_retry(func, attempt + 1, opts, from, state)
          {:retrying, state}
        end
    end
  end

  defp handle_task_result(result, func, attempt, opts, from, state) do
    {_, new_state} = handle_task_result_sync(result, func, attempt, opts, from, state)
    {:noreply, new_state}
  end

  defp schedule_retry(func, next_attempt, opts, from, state) do
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)

    n = next_attempt - 1
    shift = min(n, 50)
    delay = min(base_delay <<< shift, max_delay)

    jitter = if delay > 0, do: state.random.(delay), else: 0
    total_wait = delay + jitter

    Process.send_after(self(), {:retry, func, next_attempt, opts, from}, total_wait)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule TimeoutRetryWorkerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  # --- Fake random that always returns 0 (no jitter) ---

  defmodule ZeroRandom do
    def rand(_max), do: 0
  end

  # --- Counter to build "fail N times then succeed" functions ---

  defmodule Counter do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def increment_and_get do
      Agent.get_and_update(__MODULE__, fn n -> {n + 1, n + 1} end)
    end

    def get, do: Agent.get(__MODULE__, & &1)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      TimeoutRetryWorker.start_link(
        clock: &Clock.now/0,
        random: &ZeroRandom.rand/1
      )

    %{rw: pid}
  end

  # Helper: build a function that fails `n` times then succeeds with `value`
  defp fail_then_succeed(n, value) do
    start_supervised!({Counter, 0})

    fn ->
      attempt = Counter.increment_and_get()

      if attempt <= n do
        {:error, :boom}
      else
        {:ok, value}
      end
    end
  end

  # -------------------------------------------------------
  # Immediate success
  # -------------------------------------------------------

  test "returns immediately when function succeeds on first try", %{rw: rw} do
    func = fn -> {:ok, 42} end

    assert {:ok, 42} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )
  end

  test "does not retry when function succeeds on first try", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:ok, :yep}
    end

    assert {:ok, :yep} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 5,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )

    assert Counter.get() == 1
  end

  # -------------------------------------------------------
  # Retries then succeeds
  # -------------------------------------------------------

  test "retries and succeeds on the Nth attempt", %{rw: rw} do
    func = fail_then_succeed(3, :recovered)

    assert {:ok, :recovered} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 5,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )

    # 3 failures + 1 success = 4 total calls
    assert Counter.get() == 4
  end

  test "succeeds on the very last retry", %{rw: rw} do
    func = fail_then_succeed(3, :last_chance)

    assert {:ok, :last_chance} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )

    assert Counter.get() == 4
  end

  # -------------------------------------------------------
  # Max retries exhausted
  # -------------------------------------------------------

  test "returns error when all retries are exhausted", %{rw: rw} do
    func = fail_then_succeed(10, :never)

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )

    assert Counter.get() == 4
  end

  test "max_retries of 0 means no retries at all", %{rw: rw} do
    func = fail_then_succeed(5, :nope)

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 0,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )

    assert Counter.get() == 1
  end

  # -------------------------------------------------------
  # Per-attempt timeout enforcement
  # -------------------------------------------------------

  test "times out a slow function and retries", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      if attempt <= 1 do
        # Simulate a hang — sleep longer than the timeout
        Process.sleep(500)
        {:ok, :should_not_reach}
      else
        {:ok, :recovered_after_timeout}
      end
    end

    assert {:ok, :recovered_after_timeout} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 50,
               attempt_timeout_ms: 100
             )

    assert Counter.get() == 2
  end

  test "returns timeout as last reason when all attempts time out", %{rw: rw} do
    func = fn ->
      Process.sleep(500)
      {:ok, :never_reaches}
    end

    assert {:error, :max_retries_exceeded, :timeout} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 50,
               attempt_timeout_ms: 50
             )
  end

  # -------------------------------------------------------
  # Concurrent executions are independent
  # -------------------------------------------------------

  test "multiple concurrent executions don't block each other", %{rw: rw} do
    # func1 succeeds immediately
    func1 = fn -> {:ok, :fast} end

    # func2 fails once then succeeds
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func2 = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      if n <= 1, do: {:error, :not_yet}, else: {:ok, :slow}
    end

    task1 =
      Task.async(fn ->
        TimeoutRetryWorker.execute(rw, func1,
          max_retries: 3,
          base_delay_ms: 100,
          attempt_timeout_ms: 5_000
        )
      end)

    task2 =
      Task.async(fn ->
        TimeoutRetryWorker.execute(rw, func2,
          max_retries: 3,
          base_delay_ms: 100,
          attempt_timeout_ms: 5_000
        )
      end)

    # func1 should return immediately
    assert {:ok, :fast} = Task.await(task1, 2_000)

    # func2 retries and eventually succeeds
    assert {:ok, :slow} = Task.await(task2, 5_000)
    Agent.stop(agent)
  end

  # -------------------------------------------------------
  # Propagates the last error reason
  # -------------------------------------------------------

  test "returns the last error reason on exhaustion", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      {:error, :"fail_#{n}"}
    end

    assert {:error, :max_retries_exceeded, last_reason} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 50,
               attempt_timeout_ms: 5_000
             )

    assert last_reason == :fail_3

    Agent.stop(agent)
  end

  # -------------------------------------------------------
  # Timeout mixed with normal errors
  # -------------------------------------------------------

  test "timeout on first attempt then error then success", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      case attempt do
        1 ->
          Process.sleep(500)
          {:ok, :too_slow}

        2 ->
          {:error, :transient_failure}

        _ ->
          {:ok, :finally}
      end
    end

    assert {:ok, :finally} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 5,
               base_delay_ms: 50,
               attempt_timeout_ms: 100
             )

    assert Counter.get() == 3
  end

  # -------------------------------------------------------
  # Default options
  # -------------------------------------------------------

  test "uses default options when not specified", %{rw: rw} do
    func = fn -> {:ok, :defaults_work} end
    assert {:ok, :defaults_work} = TimeoutRetryWorker.execute(rw, func, [])
  end

  # =======================================================
  # Added coverage: defaults, backoff arithmetic, jitter source
  # =======================================================

  # A jitter source that records every `delay` it is handed and cancels the
  # wait (jitter = -delay, so `delay + jitter == 0`), letting us read the exact
  # delay sequence without spending wall-clock time on backoff.
  defp recording_random do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    random = fn delay ->
      Agent.update(agent, &[delay | &1])
      -delay
    end

    {agent, random}
  end

  defp recorded_delays(agent), do: agent |> Agent.get(& &1) |> Enum.reverse()

  defp always_fails, do: fn -> {:error, :boom} end

  defp elapsed_ms(fun) do
    started = System.monotonic_time(:millisecond)
    fun.()
    System.monotonic_time(:millisecond) - started
  end

  # `max_retries` defaults to 3, so `func` may run at most 3 + 1 = 4 times.
  test "default max_retries of 3 allows exactly four invocations" do
    worker = start_supervised!({TimeoutRetryWorker, [random: fn _max -> 0 end]})
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(calls, &(&1 + 1))
      {:error, :boom}
    end

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, func,
               base_delay_ms: 1,
               max_delay_ms: 1,
               attempt_timeout_ms: 1_000
             )

    assert Agent.get(calls, & &1) == 4
    Agent.stop(calls)
  end

  # Delay for retry N is min(base_delay_ms * 2^(N-1), max_delay_ms), and
  # base_delay_ms defaults to 100: retries 1, 2, 3 use 100, 200, 400.
  test "default base_delay_ms of 100 doubles for each successive retry" do
    {agent, random} = recording_random()
    worker = start_supervised!({TimeoutRetryWorker, [random: random]})

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, always_fails(),
               max_retries: 3,
               attempt_timeout_ms: 1_000
             )

    assert recorded_delays(agent) == [100, 200, 400]
    Agent.stop(agent)
  end

  # The jitter function is called with the computed delay whenever the delay is
  # positive; max_delay_ms caps the delay, here at 1 for every retry.
  test "jitter function is called with the capped delay on every positive-delay retry" do
    {agent, random} = recording_random()
    worker = start_supervised!({TimeoutRetryWorker, [random: random]})

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, always_fails(),
               max_retries: 3,
               base_delay_ms: 1,
               max_delay_ms: 1,
               attempt_timeout_ms: 1_000
             )

    assert recorded_delays(agent) == [1, 1, 1]
    Agent.stop(agent)
  end

  # A zero delay must not consult the jitter function at all.
  test "zero delay never calls the jitter function yet still retries" do
    {agent, random} = recording_random()
    worker = start_supervised!({TimeoutRetryWorker, [random: random]})
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(calls, &(&1 + 1))
      {:error, :boom}
    end

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, func,
               max_retries: 3,
               base_delay_ms: 0,
               max_delay_ms: 100,
               attempt_timeout_ms: 1_000
             )

    assert recorded_delays(agent) == []
    assert Agent.get(calls, & &1) == 4

    Agent.stop(calls)
    Agent.stop(agent)
  end

  # With a zero delay the jitter is 0, so the total wait is 0: a long chain of
  # zero-delay retries must cost no more wall-clock than the same chain whose
  # jitter cancels the delay out to a zero wait.
  test "zero delay waits nothing rather than a millisecond per retry" do
    retries = 400
    worker = start_supervised!({TimeoutRetryWorker, [random: fn delay -> -delay end]})

    cancelled = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 1,
                 max_delay_ms: 1,
                 attempt_timeout_ms: 1_000
               )
    end

    zeroed = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 0,
                 max_delay_ms: 0,
                 attempt_timeout_ms: 1_000
               )
    end

    baseline_ms = elapsed_ms(cancelled)
    zero_delay_ms = elapsed_ms(zeroed)

    # A 1 ms wait per retry would add ~400 ms over the zero-wait baseline.
    assert zero_delay_ms - baseline_ms < 200
  end

  # The default jitter source yields values in 0..max-1, so a delay of 1 admits
  # only jitter 0: each retry waits exactly 1 ms — never 0 ms, never 2 ms.
  test "default jitter source keeps a one-millisecond delay at a one-millisecond wait" do
    retries = 300
    worker = start_supervised!({TimeoutRetryWorker, []})

    overhead = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 0,
                 max_delay_ms: 0,
                 attempt_timeout_ms: 1_000
               )
    end

    jittered = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 1,
                 max_delay_ms: 1,
                 attempt_timeout_ms: 1_000
               )
    end

    overhead_ms = elapsed_ms(overhead)
    waited_ms = elapsed_ms(jittered) - overhead_ms

    # 300 retries x exactly 1 ms of wait, minus the no-wait overhead baseline.
    assert waited_ms >= 100
    assert waited_ms <= 560
  end

  test "abnormal task exit yields task_crashed reason on the final exhausted attempt", %{rw: rw} do
    func = fn -> exit(:kaboom) end

    assert {:error, :max_retries_exceeded, {:task_crashed, :kaboom}} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 0,
               attempt_timeout_ms: 1_000
             )
  end

  test "abnormal task exit is retryable so a later attempt can still succeed", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      if n == 1, do: exit(:kaboom), else: {:ok, :recovered}
    end

    assert {:ok, :recovered} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 0,
               max_delay_ms: 0,
               attempt_timeout_ms: 1_000
             )

    Agent.stop(agent)
  end

  test "registers under the :name option and serves calls addressed by that name" do
    {:ok, _pid} =
      TimeoutRetryWorker.start_link(
        name: :trw_named_worker,
        random: &ZeroRandom.rand/1
      )

    assert {:ok, :via_name} =
             TimeoutRetryWorker.execute(:trw_named_worker, fn -> {:ok, :via_name} end,
               max_retries: 0
             )
  end

  test "start_link with no arguments starts a usable worker" do
    assert {:ok, pid} = TimeoutRetryWorker.start_link()

    assert {:ok, :no_arg} =
             TimeoutRetryWorker.execute(pid, fn -> {:ok, :no_arg} end, max_retries: 0)
  end

  test "execute called with only server and func uses the default option set", %{rw: rw} do
    # TODO
  end

  test "re-running execute on the same server restarts attempt counting from zero", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(agent, &(&1 + 1))
      {:error, :boom}
    end

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 0,
               max_delay_ms: 0,
               attempt_timeout_ms: 1_000
             )

    assert Agent.get(agent, & &1) == 3

    Agent.update(agent, fn _ -> 0 end)

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 0,
               max_delay_ms: 0,
               attempt_timeout_ms: 1_000
             )

    assert Agent.get(agent, & &1) == 3

    Agent.stop(agent)
  end

  test "one caller's slow in-flight attempt never blocks another caller", %{rw: rw} do
    test_pid = self()

    # Parks inside its attempt Task until released — a long-running attempt
    # nowhere near its generous 60s timeout.
    slow = fn ->
      send(test_pid, {:slow_started, self()})

      receive do
        :release -> {:ok, :released}
      end
    end

    slow_task =
      Task.async(fn ->
        TimeoutRetryWorker.execute(rw, slow, attempt_timeout_ms: 60_000)
      end)

    assert_receive {:slow_started, slow_pid}, 1_000

    # With that attempt in flight, a second caller must complete promptly:
    # the server may not sit in a blocking yield on the first attempt.
    fast_task =
      Task.async(fn ->
        TimeoutRetryWorker.execute(rw, fn -> {:ok, :fast} end)
      end)

    assert {:ok, :fast} = Task.await(fast_task, 1_000)

    send(slow_pid, :release)
    assert {:ok, :released} = Task.await(slow_task, 1_000)
  end
end
```
