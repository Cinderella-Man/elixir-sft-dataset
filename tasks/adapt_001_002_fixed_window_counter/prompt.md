# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

## Existing code (your starting point)

```elixir
defmodule RateLimiter do
  @moduledoc """
  A GenServer that enforces per-key rate limits using a sliding window algorithm.

  Each key is tracked independently via a list of request timestamps.
  On every `check/4` call, timestamps outside the current window are pruned,
  and the request is allowed only if the remaining count is within the limit.

  Expired entries are garbage-collected on a configurable periodic sweep so the
  process never leaks memory for keys that stop receiving traffic.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
                                (default: `fn -> System.monotonic_time(:millisecond) end`)
    * `:cleanup_interval_ms`  – how often the periodic sweep runs in ms (default: 60_000)

  ## Examples

      iex> {:ok, pid} = RateLimiter.start_link([])
      iex> {:ok, 4} = RateLimiter.check(pid, "user:1", 5, 1_000)
      iex> {:ok, 3} = RateLimiter.check(pid, "user:1", 5, 1_000)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the RateLimiter process and links it to the caller.

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
  Checks whether a request for `key` is allowed under the given limits.

  Returns `{:ok, remaining}` when the request is accepted, where `remaining`
  is the number of additional requests the caller may make in this window.

  Returns `{:error, :rate_limited, retry_after_ms}` when the limit has been
  reached.  `retry_after_ms` is the minimum wait (in milliseconds) before the
  oldest tracked request falls outside the window.
  """
  @spec check(GenServer.server(), term(), pos_integer(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :rate_limited, non_neg_integer()}
  def check(server, key, max_requests, window_ms)
      when is_integer(max_requests) and max_requests > 0 and
             is_integer(window_ms) and window_ms > 0 do
    GenServer.call(server, {:check, key, max_requests, window_ms})
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
       # %{key => {[timestamp], window_ms}}
       keys: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:check, key, max_requests, window_ms}, _from, state) do
    now = state.clock.()

    # Fetch existing timestamps for this key (or empty list).
    {timestamps, _old_window} = Map.get(state.keys, key, {[], window_ms})

    # Prune timestamps that have fallen outside the sliding window.
    window_start = now - window_ms
    active = Enum.filter(timestamps, fn ts -> ts > window_start end)

    count = length(active)

    if count < max_requests do
      # Allow the request – record its timestamp.
      updated = [now | active]
      remaining = max_requests - count - 1

      new_keys = Map.put(state.keys, key, {updated, window_ms})
      {:reply, {:ok, remaining}, %{state | keys: new_keys}}
    else
      # Denied – compute how long until the oldest active entry expires.
      oldest = List.last(active)
      retry_after = oldest + window_ms - now
      retry_after = max(retry_after, 1)

      # Update state with the pruned list even on failure
      new_state = put_in(state.keys[key], {active, window_ms})

      {:reply, {:error, :rate_limited, retry_after}, new_state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      state.keys
      |> Enum.reduce(%{}, fn {key, {timestamps, window_ms}}, acc ->
        window_start = now - window_ms
        active = Enum.filter(timestamps, fn ts -> ts > window_start end)

        # Drop the key entirely when no active timestamps remain.
        if active == [] do
          acc
        else
          Map.put(acc, key, {active, window_ms})
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | keys: cleaned}}
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

## New specification

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
