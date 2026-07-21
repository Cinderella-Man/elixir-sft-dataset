# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule RetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff and jitter upon failure.
  """

  use GenServer
  import Bitwise

  # --- Public API ---

  @doc """
  Starts the RetryWorker GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Executes a function with exponential backoff. Returns `{:ok, result}` or
  `{:error, :max_retries_exceeded, last_reason}`.
  """
  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()} | {:error, :max_retries_exceeded, any()}
  def execute(server, func, opts \\ []) do
    # Use :infinity because retries can take a long time
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    random = Keyword.get(opts, :random, fn max -> :rand.uniform(max) - 1 end)
    {:ok, %{clock: clock, random: random}}
  end

  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    # Attempt 0 is the initial call
    do_execute(func, 0, opts, from, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry, func, attempt, opts, from}, state) do
    do_execute(func, attempt, opts, from, state)
    {:noreply, state}
  end

  # --- Private Helpers ---

  defp do_execute(func, attempt, opts, from, state) do
    max_retries = Keyword.get(opts, :max_retries, 3)

    case func.() do
      {:ok, result} ->
        GenServer.reply(from, {:ok, result})

      {:error, reason} ->
        if attempt >= max_retries do
          GenServer.reply(from, {:error, :max_retries_exceeded, reason})
        else
          schedule_retry(func, attempt + 1, opts, from, state)
        end
    end
  end

  defp schedule_retry(func, next_attempt, opts, from, state) do
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)

    # N=0 for the first retry (next_attempt 1) to get base_delay * 1
    n = next_attempt - 1
    shift = min(n, 50)
    delay = min(base_delay <<< shift, max_delay)

    jitter = if delay > 0, do: state.random.(delay), else: 0
    total_wait = delay + jitter

    Process.send_after(self(), {:retry, func, next_attempt, opts, from}, total_wait)
  end
end
```

## New specification

Write me an Elixir GenServer module called `BudgetRetryWorker` that executes a function with retries governed by a total time budget and decorrelated jitter.

I need these functions in the public API:

- `BudgetRetryWorker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:random` option which is a two-arity function that takes `(min, max)` and returns a random integer in `min..max`. If not provided, default to `fn min, max -> min + :rand.uniform(max - min + 1) - 1 end`. It should also accept a `:name` option for process registration.

- `BudgetRetryWorker.execute(server, func, opts)` which attempts to run the zero-arity function `func`. If `func` returns `{:ok, result}`, return `{:ok, result}` immediately. If `func` returns `{:error, reason}`, schedule a retry if there is still time remaining in the budget. The opts keyword list must support: `:budget_ms` (integer, default 30_000 — total wall-clock time allowed from the first attempt), `:base_delay_ms` (integer, default 100), and `:max_delay_ms` (integer, default 10_000). The call should block the caller until the function eventually succeeds or the time budget is exhausted. When the budget is exhausted return `{:error, :budget_exhausted, reason, attempts}` where `reason` is the last error reason and `attempts` is the total number of attempts made (including the initial one).

The backoff uses **decorrelated jitter** (AWS-style). Track `prev_delay` per execution, starting at `base_delay_ms`. On each retry, compute `next_delay = random(base_delay_ms, prev_delay * 3)`, then cap it: `capped_delay = min(next_delay, max_delay_ms)`. The actual wait is `capped_delay`. Before scheduling a retry, check whether `elapsed_since_start + capped_delay` would exceed `budget_ms`. If it would, do NOT schedule the retry — instead immediately return the budget-exhausted error. Update `prev_delay = capped_delay` for the next iteration.

Elapsed time is calculated by calling the injected `:clock` function and comparing to the timestamp recorded when the execution first started.

Each execution must run OFF the server's call path (e.g. a spawned worker that replies via `GenServer.reply/2`) so the GenServer never blocks other callers while an execution waits. Waits must not busy-spin: sleep in short bounded `receive ... after` ticks between clock checks, so a fake clock can drive the wait deterministically while a real clock never pegs a scheduler.

The clock is read exactly once when an execution starts and exactly once after each failed attempt; that single post-attempt reading drives BOTH the budget check (`elapsed + capped_delay > budget_ms` → give up) and the wait target (`now + capped_delay`). The budget is never re-checked when the wait completes — the next reading happens after the next failed attempt.

The GenServer should support multiple concurrent `execute` calls — each tracked independently so that one caller's retry schedule doesn't block another caller's work. Use `GenServer.reply/2` to respond asynchronously once a given execution completes or exhausts its budget.

The function passed to execute will be called inside the GenServer process. Each retry should call the function again fresh.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
