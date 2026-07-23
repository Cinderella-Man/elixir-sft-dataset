# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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

Write me an Elixir GenServer module called `ClassifiedRetryWorker` that executes a function with exponential backoff and classifies errors as transient (retryable) or permanent (non-retryable), with an optional on_retry callback.

I need these functions in the public API:

- `ClassifiedRetryWorker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:random` option which is a one-arity function that takes a max integer and returns a random integer in `0..max-1`. If not provided, default to `fn max -> :rand.uniform(max) - 1 end`. It should also accept a `:name` option for process registration.

- `ClassifiedRetryWorker.execute(server, func, opts)` which attempts to run the zero-arity function `func`. The function must return one of three shapes:
  - `{:ok, result}` — success, return `{:ok, result}` to caller immediately.
  - `{:error, :transient, reason}` — a retryable failure, schedule a retry with exponential backoff.
  - `{:error, :permanent, reason}` — a non-retryable failure, return `{:error, :permanent, reason}` to caller immediately with no retries.

  The opts keyword list must support: `:max_retries` (integer, default 3), `:base_delay_ms` (integer, default 100), `:max_delay_ms` (integer, default 10_000), and `:on_retry` — an optional 3-arity callback function `fn attempt, reason, delay -> ... end` that is called inside the GenServer before each retry is scheduled. The `attempt` is the upcoming attempt number (1-indexed, so the first retry is attempt 1), `reason` is the error reason from the failed attempt, and `delay` is the computed total delay (including jitter). If `:on_retry` is not provided, no callback is invoked.

The backoff delay for the Nth retry (1-indexed, so the first retry is N=1) should be calculated as `min(base_delay_ms * 2^(N-1), max_delay_ms)` — so with the default `base_delay_ms` of 100 the first retry's base delay is 100, the second is 200, the third is 400, and so on. Then add random jitter in the range `0..delay-1` on top, so the actual wait is `delay + jitter` where `jitter` is obtained by calling the injected `:random` function with this capped `delay` as the argument. The wait itself is MEASURED AGAINST the injected `:clock`: schedule short ticks to yourself with `Process.send_after` (so the GenServer never blocks other callers) and run the retry once the clock reaches `scheduled_at + total_wait` — a fake clock therefore drives retries deterministically, and a retry must NOT fire while the clock still reads below its target.

When all retries are exhausted on transient errors, return `{:error, :retries_exhausted, reason}` where reason is the last transient error reason.

The GenServer should support multiple concurrent `execute` calls — each tracked independently so that one caller's retry schedule doesn't block another caller's work. Use `GenServer.reply/2` to respond asynchronously once a given execution completes or exhausts retries.

The function passed to execute will be called inside the GenServer process. Each retry should call the function again fresh. Note that a function may return transient errors on some attempts and a permanent error on a later attempt — the permanent error should immediately stop retries regardless of remaining retry budget.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
