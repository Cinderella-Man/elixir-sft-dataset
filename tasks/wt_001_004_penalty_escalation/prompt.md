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

# `PenaltyLimiter` — per-key rate limiter with escalating penalties

Single-file Elixir GenServer module `PenaltyLimiter` enforcing per-key sliding-window rate limits plus a second layer of escalating cooldowns for repeat offenders. When a key is rate-limited it earns a "strike"; strikes accumulate, and each strike imposes a cooldown that must elapse before the key can be evaluated against the normal rate limit again. More misbehavior → longer lockout. OTP standard library only, no external dependencies. Deliver the complete module in a single file.

**Public API — `start_link/1`**
- `PenaltyLimiter.start_link(opts)` starts the process.
- Accepts `:clock`, a zero-arity function returning the current time in milliseconds; default `fn -> System.monotonic_time(:millisecond) end`.
- Accepts `:name` for process registration.
- Accepts `:cleanup_interval_ms` (see Cleanup).

**Public API — `check/5`**
- `PenaltyLimiter.check(server, key, max_requests, window_ms, penalty_ladder)` evaluates a request.
- `penalty_ladder` is a list of cooldown durations in milliseconds indexed by strike count, e.g. `[1_000, 5_000, 30_000, 300_000]` means "first strike = 1s cooldown, second = 5s, third = 30s, fourth and beyond = 5min".
- Each key is tracked independently.

**Return values**
- `{:ok, remaining}` — request allowed under the normal sliding-window limit. `remaining` is the number of further requests still allowed in the current window *after* this one — i.e. `max_requests` minus the number of window slots now occupied (first of three allowed requests returns `{:ok, 2}`, then `{:ok, 1}`, then `{:ok, 0}`).
- `{:error, :rate_limited, retry_after_ms, strike_count}` — rejected because the normal limit is exceeded. A strike is recorded. `retry_after_ms` is the larger of (time until the oldest window entry expires) and (the new strike's cooldown from the ladder).
- `{:error, :cooling_down, retry_after_ms, strike_count}` — rejected because an active cooldown from a previous strike is still in effect. No new strike is recorded (do not compound penalties for retrying during a cooldown). `retry_after_ms` is the remaining cooldown.

**Per-key internal state**
- List of request timestamps (for the sliding window).
- Current strike count.
- Time the last strike was issued (for decay calculation).
- Time the current cooldown ends.

**Strike decay**
- Strikes persist across window boundaries and only decay with time.
- A key's strike count drops by one for every `window_ms * 10` that passes with no new strikes. This is not configurable — a fifth argument would overcomplicate the signature; use the `window_ms * 10` rule.
- Decay is evaluated lazily at each `check` call: one strike removed per full `window_ms * 10` period elapsed since the last strike — an elapsed time of exactly one period already removes one strike.
- For each strike removed, the "last strike" reference time advances by one full period (it does not reset to the current time), so further decay stays on the original schedule.

**Decay forgives cooldowns**
- Whenever at least one strike decays, any outstanding cooldown is cancelled and the request is evaluated against the normal sliding-window limit.
- `:cooling_down` is only returned while no strike has decayed since the cooldown was recorded.
- When the strike count decays to zero the key resets entirely, as if never seen.

**Cooldown / window bookkeeping**
- The cooldown recorded with a new strike ends exactly `retry_after_ms` — the value returned in the `:rate_limited` tuple, i.e. the max defined above — after the moment the strike was issued.
- A rejected request's timestamp is not added to the sliding window; only allowed requests consume window slots.

**Cleanup**
- Run a periodic cleanup using `Process.send_after` every 60 seconds, configurable via the `:cleanup_interval_ms` option.
- Cleanup removes keys whose timestamps have all expired AND whose strike count has decayed to zero AND whose cooldown has elapsed — i.e., keys indistinguishable from never-seen keys.
- `:cleanup_interval_ms` may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.
- Sending the server process a bare `:cleanup` message performs one cleanup pass immediately — the same work the periodic timer performs.

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
  @doc """
  Checks a request under `key` against the limit, escalating the cooldown through
  `penalty_ladder` on repeated violations. Returns `{:ok, remaining}`, or an
  `{:error, reason, ...}` tuple when rate-limited or cooling down.
  """
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
    %{timestamps: [], strikes: 0, last_strike_at: nil, cooldown_end: nil, window_ms: nil}
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

    # An elapsed cooldown is cleared before the window is evaluated.
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

    # Timestamps are stored newest-first, so the scan stops at the first
    # expired entry.
    active = Enum.take_while(entry.timestamps, fn ts -> ts > window_start end)
    count = length(active)

    if count < max_requests do
      new_entry = %{entry | timestamps: [now | active], cooldown_end: nil, window_ms: window_ms}
      remaining = max_requests - count - 1

      {:reply, {:ok, remaining}, %{state | keys: Map.put(state.keys, key, new_entry)}}
    else
      new_strikes = entry.strikes + 1
      cooldown_ms = ladder_value(ladder, new_strikes)

      # Newest-first order makes the last active entry the oldest one.
      oldest = List.last(active)
      window_retry = oldest + window_ms - now

      # retry_after covers both the window expiry and the new strike's cooldown.
      retry_after = max(max(window_retry, cooldown_ms), 1)

      new_entry = %{
        entry
        | # A rejected request does not consume a window slot.
          timestamps: active,
          strikes: new_strikes,
          last_strike_at: now,
          # The cooldown ends exactly retry_after past the moment the strike
          # was issued.
          cooldown_end: now + retry_after,
          window_ms: window_ms
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

        # Decay forgives cooldowns: once any strike decays, an outstanding
        # cooldown is cancelled and the next request is evaluated against the
        # normal sliding-window limit.
        %{
          entry
          | strikes: new_strikes,
            last_strike_at: new_last,
            cooldown_end: nil
        }
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      state.keys
      |> Enum.reject(fn {_key, entry} -> removable?(entry, now) end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | keys: cleaned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # A key is removed only when it has become indistinguishable from a
  # never-seen key: every timestamp has expired (judged against the window the
  # key was last checked with), the strike count has fully decayed, and no
  # cooldown is outstanding. Decay is computed here only to DECIDE removal —
  # retained entries keep their stored state, so decay still materializes
  # lazily at the next `check`.
  defp removable?(%{window_ms: nil}, _now), do: false

  defp removable?(entry, now) do
    decayed = decay_strikes(entry, now, entry.window_ms)
    window_start = now - entry.window_ms

    Enum.all?(decayed.timestamps, fn ts -> ts <= window_start end) and
      decayed.strikes == 0 and
      (decayed.cooldown_end == nil or decayed.cooldown_end <= now)
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```
