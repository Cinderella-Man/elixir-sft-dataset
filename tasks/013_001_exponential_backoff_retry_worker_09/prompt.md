# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `RetryWorker` that executes a function with exponential backoff and jitter on failure.

I need these functions in the public API:

- `RetryWorker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:random` option which is a one-arity function that takes a max integer and returns a random integer in `0..max-1`. If not provided, default to `fn max -> :rand.uniform(max) - 1 end`. It should also accept a `:name` option for process registration.

- `RetryWorker.execute(server, func, opts)` which attempts to run the zero-arity function `func`. If `func` returns `{:ok, result}`, return `{:ok, result}` immediately. If `func` returns `{:error, reason}`, schedule a retry with exponential backoff. The opts keyword list must support: `:max_retries` (integer, default 3), `:base_delay_ms` (integer, default 100), and `:max_delay_ms` (integer, default 10_000). The call should block the caller until the function eventually succeeds or all retries are exhausted. When all retries are exhausted return `{:error, :max_retries_exceeded, reason}` where reason is the last error reason.

The backoff delay for attempt N (0-indexed, so first retry is attempt 1) should be calculated as `min(base_delay_ms * 2^N, max_delay_ms)`. Then add random jitter in the range `0..delay-1` on top, so the actual wait is `delay + jitter` where jitter is obtained by calling the injected `:random` function with `delay` as the argument. Retries must be scheduled using `Process.send_after` so the GenServer doesn't block other callers while waiting.

The GenServer should support multiple concurrent `execute` calls — each tracked independently so that one caller's retry schedule doesn't block another caller's work. Use `GenServer.reply/2` to respond asynchronously once a given execution completes or exhausts retries.

The function passed to execute will be called inside the GenServer process. Each retry should call the function again fresh.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Behavior I need pinned down

Please make the module behave exactly as described below — these are the details I care about and will rely on.

### `start_link/1`

- `opts` defaults to `[]`, so `RetryWorker.start_link()` must work and start a process with the default clock and default random function.
- Returns whatever `GenServer.start_link/3` returns: `{:ok, pid}` on success, `{:error, {:already_started, pid}}` if the `:name` is already taken.
- When `:name` is absent (or `nil`), the process starts unregistered; when present, it is registered under that name and may be addressed by name in `execute/3`.
- The `:clock` and `:random` functions are resolved once at startup and held for the lifetime of the process; they apply to every subsequent `execute/3` call on that server. Note that `:clock` is only a hook I want available in the process state — the delay itself is realized by the timer, not by reading the clock, so an injected clock has no observable effect on wait times.
- Any other keys in `opts` are ignored (no validation, no crash).

### `execute/3`

- `opts` defaults to `[]`, so `RetryWorker.execute(server, func)` must work and use all default retry options.
- The call must not time out on its own: a slow retry sequence (a long backoff chain) must never produce a caller timeout exit. The caller blocks for as long as the retry schedule takes.
- The result is exactly one of:
  - `{:ok, result}` — some attempt returned `{:ok, result}`; `result` is passed through unchanged.
  - `{:error, :max_retries_exceeded, reason}` — every allowed attempt returned `{:error, reason}`; `reason` is the reason from the **last** failing attempt (earlier reasons are discarded, and reasons may differ between attempts).
- Attempt counting: the initial invocation is attempt 0, the first retry is attempt 1, and so on. With `max_retries: N` the function is invoked at most `N + 1` times (1 initial + N retries).
  - `max_retries: 0` ⇒ the function is invoked exactly once; if it fails, the caller immediately gets `{:error, :max_retries_exceeded, reason}` with no delay and no timer.
  - A negative `max_retries` behaves the same as `0`: the function is still invoked once, and a failure returns the error tuple immediately.
  - Success on the initial attempt means no retry is ever scheduled and no jitter/random call is made.
- `func` is expected to return `{:ok, result}` or `{:error, reason}`. Any other return value is unsupported: the server does not try to interpret it, and the resulting failure inside the GenServer takes the process down and the calling `execute/3` exits. Same for a `func` that raises or throws — it is not rescued. Only the two documented shapes are handled.
- `func` is invoked with zero arity inside the GenServer process, both on the initial attempt and on every retry (a fresh call each time — nothing is memoized).
- Repeated `execute/3` calls on the same server are independent: the retry options are read per call from that call's `opts`, and one call's failures/state never affect another's.

### Backoff and jitter contract

For the retry with attempt number `k` (so `k = 1` for the first retry), let `n = k - 1`:

- `delay = min(base_delay_ms * 2^n, max_delay_ms)` — i.e. the first retry waits about `base_delay_ms`, the second about `2 * base_delay_ms`, and so on, clamped at `max_delay_ms`.
- Guard the exponent so a very long retry chain cannot blow up into an enormous number: the doubling exponent must saturate (cap the shift at 50). Past that point the delay stays at the clamped `max_delay_ms`. A large `max_retries` must not produce an astronomically large integer or a crash.
- `jitter = random.(delay)` when `delay > 0`. When `delay == 0` (e.g. `base_delay_ms: 0`, or `max_delay_ms: 0`), the random function is **not called at all** and jitter is `0`, so the retry is scheduled with a wait of `0`.
- The scheduled wait is `delay + jitter`. Because the jitter is added *after* clamping, the actual wait can exceed `max_delay_ms` — for a random function honoring `0..delay-1` the wait lies in `delay..(2 * delay - 1)`.
- The injected `:random` function receives the clamped `delay` as its single argument, once per scheduled retry. Its return value is added verbatim to the delay (no bounds checking), which makes the wait fully deterministic under an injected random function such as `fn _ -> 0 end`.

### Concurrency and ordering

- While one execution is waiting out its backoff, the GenServer must remain responsive: other `execute/3` calls are accepted and run their own attempts immediately. Waiting must never be done by sleeping in the server.
- Everything needed to resume an execution (the function, the attempt number, that call's options, and the caller to reply to) travels with the scheduled retry, so the server keeps no growing per-execution bookkeeping and executions cannot be confused with one another.
- Replies are delivered in completion order, not call order: a caller whose function succeeds immediately gets its reply even if an earlier caller is still retrying.
- Because attempts run inside the server process, individual `func` invocations are serialized — two attempts never run at the same instant — but the backoff waits themselves overlap freely.

## The module with `start_link` missing

```elixir
defmodule RetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff and jitter upon failure.
  """

  use GenServer
  import Bitwise

  # --- Public API ---

  def start_link(opts \\ []) do
    # TODO
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

Give me only the complete implementation of `start_link` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
