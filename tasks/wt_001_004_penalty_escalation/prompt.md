# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

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

## Module under test

```elixir
defmodule PenaltyLimiter do
  @moduledoc """
  A GenServer that enforces per-key rate limits with escalating cooldowns for
  repeat offenders.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @spec check(GenServer.server(), term(), pos_integer(), pos_integer(), [pos_integer(), ...]) ::
          {:ok, non_neg_integer()}
          | {:error, :rate_limited, non_neg_integer(), pos_integer()}
          | {:error, :cooling_down, non_neg_integer(), pos_integer()}
  def check(server, key, max_requests, window_ms, [_ | _] = penalty_ladder)
      when is_integer(max_requests) and max_requests > 0 and
             is_integer(window_ms) and window_ms > 0 do
    Enum.each(penalty_ladder, fn
      d when is_integer(d) and d > 0 ->
        :ok

      bad ->
        raise ArgumentError,
              "penalty ladder entries must be positive integers, got #{inspect(bad)}"
    end)

    GenServer.call(server, {:check, key, max_requests, window_ms, penalty_ladder})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000

  defp empty_entry do
    %{timestamps: [], strikes: 0, last_strike_at: nil, cooldown_end: nil}
  end

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       keys: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:check, key, max_requests, window_ms, ladder}, _from, state) do
    now = state.clock.()
    entry = Map.get(state.keys, key, empty_entry())

    # Step 1: decay strikes
    entry = decay_strikes(entry, now, window_ms)

    # ✅ FIX: expire cooldown if time has passed
    entry =
      if entry.cooldown_end && entry.cooldown_end <= now do
        %{entry | cooldown_end: nil}
      else
        entry
      end

    # Step 2: enforce cooldown if still active
    cond do
      entry.cooldown_end != nil and entry.cooldown_end > now ->
        retry_after = entry.cooldown_end - now

        {:reply, {:error, :cooling_down, retry_after, entry.strikes},
         %{state | keys: Map.put(state.keys, key, entry)}}

      true ->
        evaluate_window(state, key, entry, now, max_requests, window_ms, ladder)
    end
  end

  defp evaluate_window(state, key, entry, now, max_requests, window_ms, ladder) do
    window_start = now - window_ms

    # Highly efficient: stops traversing as soon as we hit expired timestamps
    active = Enum.take_while(entry.timestamps, fn ts -> ts > window_start end)
    count = length(active)

    if count < max_requests do
      # O(1) prepend
      new_entry = %{entry | timestamps: [now | active], cooldown_end: nil}
      remaining = max_requests - count - 1

      {:reply, {:ok, remaining}, %{state | keys: Map.put(state.keys, key, new_entry)}}
    else
      new_strikes = entry.strikes + 1
      cooldown_ms = ladder_value(ladder, new_strikes)

      # List.last is perfectly safe because monotonic time + prepending guarantees order
      oldest = List.last(active)
      window_retry = oldest + window_ms - now

      # Calculate the true retry duration
      retry_after = max(max(window_retry, cooldown_ms), 1)

      new_entry = %{
        entry
        | # Do NOT add 'now' for rejected requests
          timestamps: active,
          strikes: new_strikes,
          last_strike_at: now,
          # Fixed: Align stored state with returned value
          cooldown_end: now + retry_after
      }

      {:reply, {:error, :rate_limited, retry_after, new_strikes},
       %{state | keys: Map.put(state.keys, key, new_entry)}}
    end
  end

  defp ladder_value(ladder, strike_n) when strike_n >= 1 do
    idx = min(strike_n - 1, length(ladder) - 1)
    Enum.at(ladder, idx)
  end

  defp decay_strikes(%{strikes: 0} = entry, _now, _window_ms), do: entry
  defp decay_strikes(%{last_strike_at: nil} = entry, _now, _window_ms), do: entry

  defp decay_strikes(entry, now, window_ms) do
    decay_period = window_ms * 10
    elapsed = now - entry.last_strike_at
    forgive = div(elapsed, decay_period)

    cond do
      forgive <= 0 ->
        entry

      forgive >= entry.strikes ->
        empty_entry()

      true ->
        new_strikes = entry.strikes - forgive
        new_last = entry.last_strike_at + forgive * decay_period

        # ✅ Recalculate cooldown based on the NEW strike level
        # We approximate the "new cooldown" as if it started at new_last
        # using the ladder logic (same as when strike was created)
        # BUT since we don't have ladder here, safest option:

        %{
          entry
          | strikes: new_strikes,
            last_strike_at: new_last,
            # 🔑 clear stale cooldown
            cooldown_end: nil
        }
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      Enum.reduce(state.keys, %{}, fn {key, entry}, acc ->
        # NEW: drop expired timestamps
        active = Enum.take_while(entry.timestamps, fn ts -> ts > now end)
        entry = %{entry | timestamps: active}

        cooldown_active = entry.cooldown_end != nil and entry.cooldown_end > now
        has_strikes = entry.strikes > 0
        has_timestamps = active != []

        if cooldown_active or has_strikes or has_timestamps do
          Map.put(acc, key, entry)
        else
          acc
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | keys: cleaned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```
