# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `handle_info`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# ClassifiedRetryWorker Specification

## Overview

This document specifies an Elixir GenServer module named `ClassifiedRetryWorker`. The module executes a function with exponential backoff and classifies errors as transient (retryable) or permanent (non-retryable), with an optional on_retry callback.

The function passed to execute is called inside the GenServer process. Each retry calls the function again fresh. A function may return transient errors on some attempts and a permanent error on a later attempt — the permanent error must immediately stop retries regardless of remaining retry budget.

The GenServer supports multiple concurrent `execute` calls, each tracked independently so that one caller's retry schedule does not block another caller's work. `GenServer.reply/2` must be used to respond asynchronously once a given execution completes or exhausts retries.

The complete module must be delivered in a single file. Only the OTP standard library may be used — no external dependencies.

## API

The public API must include the following functions.

### `ClassifiedRetryWorker.start_link(opts)`

Starts the process. It accepts:

- A `:clock` option, which is a zero-arity function returning the current time in milliseconds. If not provided, it defaults to `fn -> System.monotonic_time(:millisecond) end`.
- A `:random` option, which is a one-arity function that takes a max integer and returns a random integer in `0..max-1`. If not provided, it defaults to `fn max -> :rand.uniform(max) - 1 end`.
- A `:name` option for process registration.

### `ClassifiedRetryWorker.execute(server, func, opts)`

Attempts to run the zero-arity function `func`. The function must return one of three shapes:

- `{:ok, result}` — success; return `{:ok, result}` to the caller immediately.
- `{:error, :transient, reason}` — a retryable failure; schedule a retry with exponential backoff.
- `{:error, :permanent, reason}` — a non-retryable failure; return `{:error, :permanent, reason}` to the caller immediately with no retries.

The opts keyword list must support:

- `:max_retries` (integer, default 3)
- `:base_delay_ms` (integer, default 100)
- `:max_delay_ms` (integer, default 10_000)
- `:on_retry` — an optional 3-arity callback function `fn attempt, reason, delay -> ... end` that is called inside the GenServer before each retry is scheduled. The `attempt` is the upcoming attempt number (1-indexed, so the first retry is attempt 1), `reason` is the error reason from the failed attempt, and `delay` is the computed total delay (including jitter). If `:on_retry` is not provided, no callback is invoked.

## Backoff and timing

The backoff delay for the Nth retry (1-indexed, so the first retry is N=1) is calculated as `min(base_delay_ms * 2^(N-1), max_delay_ms)`. With the default `base_delay_ms` of 100, the first retry's base delay is 100, the second is 200, the third is 400, and so on.

Random jitter in the range `0..delay-1` is then added on top, so the actual wait is `delay + jitter`, where `jitter` is obtained by calling the injected `:random` function with this capped `delay` as the argument.

The wait itself is MEASURED AGAINST the injected `:clock`: schedule short ticks to yourself with `Process.send_after` (so the GenServer never blocks other callers) and run the retry once the clock reaches `scheduled_at + total_wait`. A fake clock therefore drives retries deterministically, and a retry must NOT fire while the clock still reads below its target.

## Edge cases

- When all retries are exhausted on transient errors, return `{:error, :retries_exhausted, reason}`, where reason is the last transient error reason.
- A permanent error must immediately stop retries regardless of remaining retry budget, even if it follows earlier transient errors from the same execution.
- If `:on_retry` is not provided, no callback is invoked.

## The module with `handle_info` missing

```elixir
defmodule ClassifiedRetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff,
  classifying errors as transient (retryable) or permanent (non-retryable),
  with an optional on_retry callback.
  """

  use GenServer
  import Bitwise

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Runs `func`, retrying classified errors per `opts`. Returns the result."
  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()}
          | {:error, :permanent, any()}
          | {:error, :retries_exhausted, any()}
  def execute(server, func, opts \\ []) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # --- GenServer Callbacks ---

  # Real-clock granularity of the tick-gated retry wait.
  @tick_ms 1

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    random = Keyword.get(opts, :random, fn max -> :rand.uniform(max) - 1 end)
    {:ok, %{clock: clock, random: random}}
  end

  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    do_execute(func, 0, opts, from, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry_at, func, attempt, opts, from, target}, state) do
    # Tick-gated wait: re-tick until the injected clock reaches the target,
    # so a fake clock drives retries deterministically while the server keeps
    # serving other callers between ticks.
    if state.clock.() >= target do
      do_execute(func, attempt, opts, from, state)
    else
      Process.send_after(self(), {:retry_at, func, attempt, opts, from, target}, @tick_ms)
    end

    {:noreply, state}
  end

  # --- Private Helpers ---

  defp do_execute(func, attempt, opts, from, state) do
    max_retries = Keyword.get(opts, :max_retries, 3)

    case func.() do
      {:ok, result} ->
        GenServer.reply(from, {:ok, result})

      {:error, :permanent, reason} ->
        GenServer.reply(from, {:error, :permanent, reason})

      {:error, :transient, reason} ->
        if attempt >= max_retries do
          GenServer.reply(from, {:error, :retries_exhausted, reason})
        else
          schedule_retry(func, attempt + 1, opts, from, reason, state)
        end
    end
  end

  defp schedule_retry(func, next_attempt, opts, from, reason, state) do
    # TODO
  end
end
```

Output only `handle_info` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
