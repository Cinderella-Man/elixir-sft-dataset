# Fix the failing module

I asked for the following:

Write me an Elixir GenServer module called `BudgetRetryWorker` that executes a function with retries governed by a total time budget and decorrelated jitter.

I need these functions in the public API:

- `BudgetRetryWorker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:random` option which is a two-arity function that takes `(min, max)` and returns a random integer in `min..max`. If not provided, default to `fn min, max -> min + :rand.uniform(max - min + 1) - 1 end`. It should also accept a `:name` option for process registration.

- `BudgetRetryWorker.execute(server, func, opts)` which attempts to run the zero-arity function `func`. If `func` returns `{:ok, result}`, return `{:ok, result}` immediately. If `func` returns `{:error, reason}`, schedule a retry if there is still time remaining in the budget. The opts keyword list must support: `:budget_ms` (integer, default 30_000 — total wall-clock time allowed from the first attempt), `:base_delay_ms` (integer, default 100), and `:max_delay_ms` (integer, default 10_000). The call should block the caller until the function eventually succeeds or the time budget is exhausted. When the budget is exhausted return `{:error, :budget_exhausted, reason, attempts}` where `reason` is the last error reason and `attempts` is the total number of attempts made (including the initial one).

The backoff uses **decorrelated jitter** (AWS-style). Track `prev_delay` per execution, starting at `base_delay_ms`. On each retry, compute `next_delay = random(base_delay_ms, prev_delay * 3)`, then cap it: `capped_delay = min(next_delay, max_delay_ms)`. The actual wait is `capped_delay`. Before scheduling a retry, check whether `elapsed_since_start + capped_delay` would exceed `budget_ms`. If it would, do NOT schedule the retry — instead immediately return the budget-exhausted error. Update `prev_delay = capped_delay` for the next iteration.

Elapsed time is calculated by calling the injected `:clock` function and comparing to the timestamp recorded when the execution first started.

Retries must be scheduled using `Process.send_after` so the GenServer doesn't block other callers while waiting.

The GenServer should support multiple concurrent `execute` calls — each tracked independently so that one caller's retry schedule doesn't block another caller's work. Use `GenServer.reply/2` to respond asynchronously once a given execution completes or exhausts its budget.

The function passed to execute will be called inside the GenServer process. Each retry should call the function again fresh.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

Here is my current implementation, but it is failing tests:

```elixir
defmodule BudgetRetryWorker do
  @moduledoc """
  A GenServer that executes functions with retries governed by a total time
  budget and decorrelated jitter (AWS-style backoff).

  The supplied function runs inside the GenServer process. Retries are scheduled
  with `Process.send_after/3` so the server never blocks other callers while a
  given execution is waiting for its next attempt. Waiting is driven by the
  injected `:clock`, allowing deterministic, time-controlled testing.
  """

  use GenServer

  @poll_interval 1

  # --- Public API ---

  @doc """
  Starts the worker.

  Options:

    * `:clock` — zero-arity fun returning the current time in milliseconds
      (defaults to monotonic time).
    * `:random` — two-arity fun `(min, max)` returning an integer in `min..max`.
    * `:name` — optional process registration name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Runs `func`, retrying with decorrelated-jitter backoff until it succeeds or the
  time budget in `opts` is exhausted. Blocks the caller until a result is known.
  """
  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()} | {:error, :budget_exhausted, any(), pos_integer()}
  def execute(server, func, opts \\ []) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    random =
      Keyword.get(opts, :random, fn min, max ->
        min + :rand.uniform(max - min + 1) - 1
      end)

    {:ok, %{clock: clock, random: random}}
  end

  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    base_delay = Keyword.get(opts, :base_delay_ms, 100)

    exec = %{
      from: from,
      func: func,
      started_at: state.clock.(),
      base_delay: base_delay,
      budget: Keyword.get(opts, :budget_ms, 30_000),
      max_delay: Keyword.get(opts, :max_delay_ms, 10_000),
      prev_delay: base_delay,
      attempts: 0
    }

    run_attempt(exec, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:poll, exec}, state) do
    if state.clock.() >= exec.target do
      run_attempt(Map.delete(exec, :target), state)
    else
      Process.send_after(self(), {:poll, exec}, @poll_interval)
    end

    {:noreply, state}
  end

  # --- Private Helpers ---

  defp run_attempt(exec, state) do
    exec = %{exec | attempts: exec.attempts + 1}

    case exec.func.() do
      {:ok, result} ->
        GenServer.reply(exec.from, {:ok, result})

      {:error, reason} ->
        schedule_or_exhaust(exec, reason, state)
    end

    :ok
  end

  defp schedule_or_exhaust(exec, reason, state) do
    now = state.clock.()
    elapsed = now - exec.started_at

    jitter_max = exec.prev_delay * 3
    next_delay = state.random.(exec.base_delay, jitter_max)
    capped_delay = min(next_delay, exec.max_delay)

    if elapsed + capped_delay > exec.budget do
      GenServer.reply(exec.from, {:error, :budget_exhausted, reason, exec.attempts})
    else
      next_exec = %{exec | prev_delay: capped_delay, target: now + capped_delay}
      Process.send_after(self(), {:poll, next_exec}, @poll_interval)
    end
  end
end

```

The failure report:

```
Tests failed (9 failed, 0 errors):
  - test retries and succeeds within the time budget (BudgetRetryWorkerTest): {:EXIT, #PID<0.225.0>}: {{:badkey, :target}, [{BudgetRetryWorker, :schedule_or_exhaust, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 116]}, {BudgetRetryWorker, :run_attempt, 2, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 99]}, {BudgetRetryWorker, :handle_call, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 74]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test returns budget_exhausted when time runs out (BudgetRetryWorkerTest): {:EXIT, #PID<0.231.0>}: {{:badkey, :target}, [{BudgetRetryWorker, :schedule_or_exhaust, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 116]}, {BudgetRetryWorker, :run_attempt, 2, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 99]}, {BudgetRetryWorker, :handle_call, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 74]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test max_delay_ms caps the computed delay (BudgetRetryWorkerTest): {:EXIT, #PID<0.242.0>}: {{:badkey, :target}, [{BudgetRetryWorker, :schedule_or_exhaust, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 116]}, {BudgetRetryWorker, :run_attempt, 2, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 99]}, {BudgetRetryWorker, :handle_call, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 74]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test multiple concurrent executions don't block each other (BudgetRetryWorkerTest): {:EXIT, #PID<0.249.0>}: {{:badkey, :target}, [{BudgetRetryWorker, :schedule_or_exhaust, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 116]}, {BudgetRetryWorker, :run_attempt, 2, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 99]}, {BudgetRetryWorker, :handle_call, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 74]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test attempt count reflects all tries made (BudgetRetryWorkerTest): {:EXIT, #PID<0.256.0>}: {{:badkey, :target}, [{BudgetRetryWorker, :schedule_or_exhaust, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 116]}, {BudgetRetryWorker, :run_attempt, 2, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 99]}, {BudgetRetryWorker, :handle_call, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 74]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test the injected random receives (base_delay_ms, prev_delay * 3) under defaults (BudgetRetryWorkerTest): {:EXIT, #PID<0.266.0>}: {{:badkey, :target}, [{BudgetRetryWorker, :schedule_or_exhaust, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 116]}, {BudgetRetryWorker, :run_attempt, 2, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 99]}, {BudgetRetryWorker, :handle_call, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 74]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test elapsed time is measured against the recorded start timestamp (BudgetRetryWorkerTest): {:EXIT, #PID<0.273.0>}: {{:badkey, :target}, [{BudgetRetryWorker, :schedule_or_exhaust, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 116]}, {BudgetRetryWorker, :run_attempt, 2, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 99]}, {BudgetRetryWorker, :handle_call, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 74]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test a retry landing exactly on the budget boundary is still scheduled (BudgetRetryWorkerTest): {:EXIT, #PID<0.280.0>}: {{:badkey, :target}, [{BudgetRetryWorker, :schedule_or_exhaust, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 116]}, {BudgetRetryWorker, :run_attempt, 2, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 99]}, {BudgetRetryWorker, :handle_call, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 74]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
  - test budget_exhausted carries the reason from the most recent failed attempt (BudgetRetryWorkerTest): {:EXIT, #PID<0.291.0>}: {{:badkey, :target}, [{BudgetRetryWorker, :schedule_or_exhaust, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 116]}, {BudgetRetryWorker, :run_attempt, 2, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 99]}, {BudgetRetryWorker, :handle_call, 3, [file: ~c".gen_staging/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/solution.ex", line: 74]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2470]}, {:gen_server, :handle_msg, 3, [file: ~c"gen_server.erl", line: 2499]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 333]}]}
```

Find the bug and give me the corrected complete module in a single file.
<!-- minted from logs/attempts/013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01_audit/attempt_1 -->
