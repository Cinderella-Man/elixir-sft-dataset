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

Write me an Elixir GenServer module called `PenaltyLimiter` that enforces per-key rate limits with **escalating penalties** for repeat offenders.

The motivation: simple sliding-window rate limiters let a misbehaving client retry the instant their window clears. This module adds a second layer — when a key gets rate-limited, it earns a "strike." Strikes accumulate, and each strike imposes a cooldown that must elapse before the key can even be evaluated against the normal rate limit again. The more a client misbehaves, the longer they're locked out.

I need these functions in the public API:

- `PenaltyLimiter.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `PenaltyLimiter.check(server, key, max_requests, window_ms, penalty_ladder)` which evaluates a request. `penalty_ladder` is a list of cooldown durations in milliseconds indexed by strike count, e.g. `[1_000, 5_000, 30_000, 300_000]` means "first strike = 1s cooldown, second = 5s, third = 30s, fourth and beyond = 5min". Strikes persist across window boundaries and only decay with time — specifically, a key's strike count drops by one for every `window_ms * 10` that passes with no new strikes (configurable via a fifth argument would overcomplicate the signature; use the `window_ms * 10` rule).

  Possible return values:
  - `{:ok, remaining}` — request allowed under the normal sliding-window limit, where `remaining` is the remaining allowance in the current window.
  - `{:error, :rate_limited, retry_after_ms, strike_count}` — request rejected because the normal limit is exceeded. A strike has been recorded. `retry_after_ms` is the larger of (time until the oldest window entry expires) and (the new strike's cooldown from the ladder).
  - `{:error, :cooling_down, retry_after_ms, strike_count}` — request rejected because an active cooldown from a previous strike is still in effect. No new strike is recorded (you don't compound penalties for retrying during a cooldown). `retry_after_ms` is the remaining cooldown.

Each key must be tracked independently. Internally track per key: the list of request timestamps (for the sliding window), the current strike count, the time the last strike was issued (for decay calculation), and the time the current cooldown ends.

Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes keys whose timestamps have all expired AND whose strike count has decayed to zero AND whose cooldown has elapsed — i.e., keys that are indistinguishable from never-seen keys.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Additional interface contract

- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic
  timer is never scheduled — nothing runs automatically.

- Sending the server process a bare `:cleanup` message performs one cleanup
  pass immediately — the same work the periodic timer performs.

- Strike decay is evaluated lazily at each `check` call: one strike is removed for
  every full `window_ms * 10` period elapsed since the last strike — an elapsed time
  of exactly one period already removes one strike. For each strike removed, the
  "last strike" reference time advances by one full period (it does not reset to the
  current time), so further decay stays on the original schedule.

- Decay forgives cooldowns: whenever at least one strike decays, any outstanding
  cooldown is cancelled and the request is evaluated against the normal
  sliding-window limit. `:cooling_down` is only returned while no strike has decayed
  since the cooldown was recorded. When the strike count decays to zero the key
  resets entirely, as if never seen.

- The cooldown recorded with a new strike ends exactly `retry_after_ms` — the value
  returned in the `:rate_limited` tuple, i.e. the max defined above — after the
  moment the strike was issued.

- A rejected request's timestamp is not added to the sliding window; only allowed
  requests consume window slots.
