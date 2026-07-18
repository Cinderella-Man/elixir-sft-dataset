# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `init` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `RateLimiter` that enforces per-key rate limits using a sliding window algorithm.

I need these functions in the public API:

- `RateLimiter.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `RateLimiter.check(server, key, max_requests, window_ms)` which checks whether a request for the given key is allowed. If allowed, return `{:ok, remaining}` where remaining is how many more requests are available in the current window. If not allowed, return `{:error, :rate_limited, retry_after_ms}` where retry_after_ms tells the caller how long to wait.

Each key must be tracked independently — rate limiting "user:1" should have no effect on "user:2". The sliding window should work correctly at boundaries, meaning if I make 3 requests allowed per 1000ms window and I make them at time 0, then at time 1001 I should be allowed again.

You also need to make sure expired entries get cleaned up so the GenServer doesn't leak memory over time. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes any tracking data for windows that have fully expired.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Startup contract

- `start_link/1` links the new process to the caller and returns the usual
  `GenServer.on_start()` result. The `opts` argument is a keyword list and should
  default to `[]` when omitted.
- When `:name` is given it is used for process registration (so `check/4` can be
  called with either the pid or the registered name). When `:name` is absent the
  process is started unregistered. `:name` must not be passed through as part of
  the server's own configuration — it is purely a registration concern.
- `:clock` defaults to `fn -> System.monotonic_time(:millisecond) end`. Every time
  the server needs "now" — on a `check/4` and on a cleanup pass — it calls the
  configured clock function afresh. A test clock returning a fixed integer must
  therefore make time appear frozen, and a clock the caller mutates must be
  observed at its current value on the next call.
- `:cleanup_interval_ms` defaults to `60_000`.
- Starting the server performs no work other than setting up state and, if
  applicable, scheduling the first cleanup. In particular a freshly started server
  tracks zero keys.

## `check/4` contract

`check/4` is a synchronous call. It takes a `key` (any term — strings, atoms,
tuples, integers all work and are compared by value), a positive integer
`max_requests`, and a positive integer `window_ms`. Calling it with a non-integer
or non-positive `max_requests`/`window_ms` is outside the contract and may raise
a `FunctionClauseError` — guard the public function accordingly. The `key` is not
validated.

Semantics of a single call, at time `now` returned by the clock:

1. The timestamps already recorded for `key` are pruned: a timestamp is **active**
   iff `ts > now - window_ms`. So an entry recorded exactly `window_ms`
   milliseconds ago is *not* active — it has just fallen out of the window. An
   entry recorded `window_ms - 1` ms ago is still active.
2. Let `count` be the number of active timestamps.
   - If `count < max_requests`, the request is **allowed**: `now` is recorded as a
     new timestamp for `key`, and the reply is `{:ok, remaining}` where
     `remaining = max_requests - count - 1`. So the first call under a limit of 5
     returns `{:ok, 4}`, then `{:ok, 3}`, … and the last allowed call returns
     `{:ok, 0}`.
   - If `count >= max_requests`, the request is **denied** and the reply is
     `{:error, :rate_limited, retry_after_ms}`. A denied call does **not** record a
     timestamp — being rate limited never pushes the window forward, so repeatedly
     hammering a limited key does not extend the block.
3. `retry_after_ms` is computed from the **oldest** active timestamp `oldest`:
   `retry_after_ms = max(oldest + window_ms - now, 1)`. It is therefore always at
   least `1` and never `0` or negative, and it is the minimum wait after which the
   oldest tracked request drops out of the window and a slot frees up. Waiting
   exactly `retry_after_ms` and calling again must succeed (given no other calls in
   between).

Additional observable properties:

- Pruning happens on denied calls too: the stored timestamp list for the key is
  replaced with the pruned (active-only) list even when the reply is an error. A
  caller cannot observe this directly except through subsequent `check/4` results,
  which must remain consistent with the rules above.
- Boundary example that must hold: with `max_requests = 3`, `window_ms = 1000`,
  three calls at time `0` return `{:ok, 2}`, `{:ok, 1}`, `{:ok, 0}`; a fourth call
  at time `0` returns `{:error, :rate_limited, 1000}`; a call at time `1000`
  succeeds (the time-0 entries are no longer active, since `0 > 1000 - 1000` is
  false), and a call at `1001` likewise succeeds.
- Keys are fully independent: exhausting the limit for one key never affects the
  result for any other key, and an unknown/never-seen key behaves exactly like a
  key with zero active timestamps (first call returns `{:ok, max_requests - 1}`).
- `max_requests` and `window_ms` are supplied per call, not fixed at startup. The
  same key may be checked with different limits over time; the effective window
  for pruning is always the `window_ms` passed to the current call, and the
  `window_ms` most recently seen for a key is what a cleanup pass uses for that key.
- Two calls at the same clock value are both recorded; identical timestamps are
  allowed and each counts separately toward the limit.

## Cleanup contract

- Unless the interval is `:infinity`, the server schedules a `:cleanup` message to
  itself via `Process.send_after/3` at startup and re-schedules the next one at the
  end of each cleanup pass, so the sweep repeats indefinitely.
- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the
  periodic timer is never scheduled — nothing runs automatically. The server is
  otherwise fully functional; only the automatic sweep is disabled.
- Sending the server process a bare `:cleanup` message performs one cleanup pass
  immediately — the same work the periodic timer performs. This is how a caller can
  deterministically trigger a sweep with a test clock. (Note: a manually sent
  `:cleanup` also re-schedules the next timer when the interval is an integer.)
- A cleanup pass reads the clock once and, for every tracked key, prunes timestamps
  using the same "active" rule (`ts > now - window_ms`, with that key's most
  recently seen `window_ms`). A key whose active list becomes empty is **removed
  entirely** from the server's state; keys with at least one active timestamp are
  retained with their pruned list. Cleanup never changes whether a subsequent
  `check/4` is allowed — it is purely a memory reclamation pass, and running it any
  number of times (including on an empty state) is idempotent and side-effect free
  from the caller's point of view.
- The server must tolerate arbitrary unexpected messages: any message other than
  `:cleanup` is ignored and must not crash the process or alter state.

## The module with `init` missing

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

  def init(opts) do
    # TODO
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

Give me only the complete implementation of `init` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
