# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `execute` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `execute` missing

```elixir
defmodule BudgetRetryWorker do
  @moduledoc """
  A GenServer that executes functions with retries governed by a total time
  budget and decorrelated jitter (AWS-style backoff).
  """

  use GenServer

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Runs `func`, retrying with decorrelated-jitter backoff until it succeeds or the retry
  budget in `opts` is exhausted.
  """
  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()} | {:error, :budget_exhausted, any(), pos_integer()}
  def execute(server, func, opts \\ []) do
    # TODO
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
    clock_fn = state.clock
    random_fn = state.random

    spawn_link(fn ->
      result = retry_loop(func, opts, clock_fn, random_fn)
      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  # --- Private Helpers ---

  defp retry_loop(func, opts, clock_fn, random_fn) do
    started_at = clock_fn.()
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    budget = Keyword.get(opts, :budget_ms, 30_000)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)

    do_attempt(
      func,
      clock_fn,
      random_fn,
      started_at,
      base_delay,
      budget,
      max_delay,
      base_delay,
      0
    )
  end

  defp do_attempt(
         func,
         clock_fn,
         random_fn,
         started_at,
         base_delay,
         budget,
         max_delay,
         prev_delay,
         attempts
       ) do
    attempts = attempts + 1

    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        now = clock_fn.()
        elapsed = now - started_at

        jitter_max = prev_delay * 3
        next_delay = random_fn.(base_delay, jitter_max)
        capped_delay = min(next_delay, max_delay)

        if elapsed + capped_delay > budget do
          {:error, :budget_exhausted, reason, attempts}
        else
          target_time = now + capped_delay
          await_clock(target_time, clock_fn)

          do_attempt(
            func,
            clock_fn,
            random_fn,
            started_at,
            base_delay,
            budget,
            max_delay,
            capped_delay,
            attempts
          )
        end
    end
  end

  defp await_clock(target_time, clock_fn) do
    if clock_fn.() < target_time do
      receive do
      after
        0 -> await_clock(target_time, clock_fn)
      end
    end
  end
end
```

Give me only the complete implementation of `execute` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
