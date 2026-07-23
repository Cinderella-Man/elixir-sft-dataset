# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `check` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

# FixedWindowLimiter Specification

## Overview

This document specifies an Elixir GenServer module named `FixedWindowLimiter` that enforces per-key rate limits using a fixed-window counter algorithm. The complete module is to be delivered in a single file, using only the OTP standard library with no external dependencies.

The algorithm snaps time into discrete fixed windows: the window a timestamp belongs to is `div(timestamp, window_ms)`. Each `{key, window_index}` pair maintains an independent counter.

Each key is tracked independently — rate limiting `"user:1"` has no effect on `"user:2"`. Windows are absolute, not relative: with a 1000ms window, timestamps 0-999 belong to window 0, 1000-1999 belong to window 1, and so on. Consequently, the counter resets abruptly at window boundaries. This is a known property of fixed-window counters: a client could send max_requests at t=999 and max_requests again at t=1000, effectively doubling the rate at the boundary. That behavior is acceptable for this implementation and is not to be smoothed out.

## API

The public API consists of the following functions:

- `FixedWindowLimiter.start_link(opts)` starts the process. It accepts a `:clock` option, which is a zero-arity function returning the current time in milliseconds; if not provided, it defaults to `fn -> System.monotonic_time(:millisecond) end`. It also accepts a `:name` option for process registration.

- `FixedWindowLimiter.check(server, key, max_requests, window_ms)` checks whether a request for the given key is allowed. If the counter for the current window is below max_requests, the request is allowed and the counter is incremented — it returns `{:ok, remaining}`, where `remaining` is the number of additional requests still permitted in the current window after this one (that is, `max_requests` minus the new counter value; so the first of three allowed calls returns `{:ok, max_requests - 1}` and the last returns `{:ok, 0}`). If the counter has reached max_requests, it returns `{:error, :rate_limited, retry_after_ms}`, where retry_after_ms is the time until the current window ends (when the counter resets) — that is, `window_end_time - current_time`, which is always a positive integer no greater than window_ms.

## Edge cases

- Expired counter entries must be cleaned up so the GenServer does not leak memory over time. A periodic cleanup runs using `Process.send_after` every 60 seconds (configurable via the `:cleanup_interval_ms` option) that removes any counter whose window has fully ended (window_end_time < current time).

- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.

- Sending the server process a bare `:cleanup` message performs one cleanup pass immediately — the same work the periodic timer performs.

## The module with `check` missing

```elixir
defmodule FixedWindowLimiter do
  @moduledoc """
  A GenServer that enforces per-key rate limits using a fixed-window counter.

  Time is snapped into discrete windows of size `window_ms`: a timestamp `t`
  belongs to window `div(t, window_ms)`.  Each `{key, window_index}` pair has
  its own counter.  A request is allowed if the counter for the current
  window is below `max_requests`, in which case the counter is incremented.

  Because windows are absolute, counters reset abruptly at window boundaries.
  This allows up to `2 * max_requests` requests across a boundary (e.g.,
  `max_requests` at the very end of window N and another `max_requests` at
  the very start of window N+1).  That is a known property of the fixed-
  window counter algorithm and is accepted here as a tradeoff for
  implementation simplicity and O(1) state per key.

  Expired counters are pruned during a periodic sweep so the process doesn't
  leak memory for keys that stop receiving traffic.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
                                (default: `fn -> System.monotonic_time(:millisecond) end`)
    * `:cleanup_interval_ms`  – how often the periodic sweep runs in ms (default: 60_000)

  ## Examples

      iex> {:ok, pid} = FixedWindowLimiter.start_link([])
      iex> {:ok, 4} = FixedWindowLimiter.check(pid, "user:1", 5, 1_000)
      iex> {:ok, 3} = FixedWindowLimiter.check(pid, "user:1", 5, 1_000)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the FixedWindowLimiter process and links it to the caller.

  ## Options

    * `:name`                 – optional registered name
    * `:clock`                – `(-> integer())` returning now in milliseconds
    * `:cleanup_interval_ms`  – sweep interval (default `60_000`)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Checks whether a request for `key` is allowed in the current fixed window.

  Returns `{:ok, remaining}` when the request is accepted, where `remaining`
  is the number of additional requests permitted in the same window.

  Returns `{:error, :rate_limited, retry_after_ms}` when the window's counter
  has reached `max_requests`.  `retry_after_ms` is the wait (in milliseconds)
  until the current window ends and a fresh counter begins.
  """
  @spec check(GenServer.server(), term(), pos_integer(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :rate_limited, non_neg_integer()}
  def check(server, key, max_requests, window_ms)
      when is_integer(max_requests) and max_requests > 0 and
             is_integer(window_ms) and window_ms > 0 do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       # %{{key, window_index} => {count, window_end_time}}
       counters: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:check, key, max_requests, window_ms}, _from, state) do
    now = state.clock.()

    # Snap `now` into the absolute window it belongs to.
    window_index = div(now, window_ms)
    window_end = (window_index + 1) * window_ms
    counter_key = {key, window_index}

    count = Map.get(state.counters, counter_key, {0, window_end}) |> elem(0)

    if count < max_requests do
      new_count = count + 1
      remaining = max_requests - new_count
      new_counters = Map.put(state.counters, counter_key, {new_count, window_end})

      {:reply, {:ok, remaining}, %{state | counters: new_counters}}
    else
      # Counter saturated; wait until this window ends.
      retry_after = max(window_end - now, 1)
      {:reply, {:error, :rate_limited, retry_after}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      state.counters
      |> Enum.reduce(%{}, fn {ck, {count, window_end} = entry}, acc ->
        # Keep only counters whose window has not yet ended.
        if window_end > now do
          Map.put(acc, ck, entry)
        else
          _ = count
          acc
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | counters: cleaned}}
  end

  # Catch-all so unexpected messages don't crash the process.
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```

Reply with `check` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
