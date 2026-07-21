# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

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

## Test harness — implement the `# TODO` test

```elixir
defmodule PenaltyLimiterTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    # Start fresh clock at time 0 for each test
    start_supervised!({Clock, 0})

    {:ok, pid} =
      PenaltyLimiter.start_link(
        clock: &Clock.now/0,
        # disable auto-cleanup in tests
        cleanup_interval_ms: :infinity
      )

    # Common ladder used across most tests
    %{pl: pid, ladder: [1_000, 5_000, 30_000]}
  end

  # -------------------------------------------------------
  # Basic allow / reject
  # -------------------------------------------------------

  test "allows requests within the limit", %{pl: pl, ladder: ladder} do
    assert {:ok, 2} = PenaltyLimiter.check(pl, "user:1", 3, 1_000, ladder)
    assert {:ok, 1} = PenaltyLimiter.check(pl, "user:1", 3, 1_000, ladder)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "user:1", 3, 1_000, ladder)
  end

  test "rejects the request that exceeds the limit and records a strike", %{
    pl: pl,
    ladder: ladder
  } do
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    assert {:error, :rate_limited, retry_after, 1} =
             PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # retry_after must cover both the window expiry and the first-strike cooldown (1_000ms).
    assert retry_after >= 1_000
  end

  # -------------------------------------------------------
  # Cooldown behaviour
  # -------------------------------------------------------

  test "rejection during cooldown returns :cooling_down without new strike", %{
    pl: pl,
    ladder: ladder
  } do
    # Burn through the window and earn strike 1
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # With the default ladder the first cooldown (1_000ms) ends at the same
    # moment the window clears, so the two effects cannot be told apart. Use a
    # separate limiter with a longer first cooldown so the window clears while
    # the cooldown is still active.
    {:ok, pl2} = PenaltyLimiter.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)
    long_ladder = [5_000, 30_000]

    for _ <- 1..3, do: PenaltyLimiter.check(pl2, "k", 3, 1_000, long_ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl2, "k", 3, 1_000, long_ladder)

    # Advance past the window (1_001ms) but well within the 5_000ms cooldown.
    Clock.advance(1_500)

    # Should be :cooling_down, strike count stays at 1 (no compounding).
    assert {:error, :cooling_down, retry_after, 1} =
             PenaltyLimiter.check(pl2, "k", 3, 1_000, long_ladder)

    # Cooldown started at t=0, ends at t=5000. We're at t=1500.
    assert retry_after > 3_000 and retry_after <= 5_000

    # Repeated attempts during cooldown should keep strike count at 1.
    for _ <- 1..5 do
      assert {:error, :cooling_down, _, 1} =
               PenaltyLimiter.check(pl2, "k", 3, 1_000, long_ladder)
    end
  end

  test "cooldown elapses and normal requests resume", %{pl: pl, ladder: ladder} do
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Advance past cooldown and window
    Clock.advance(1_500)

    # Now allowed again
    assert {:ok, _} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end

  # -------------------------------------------------------
  # Strike escalation
  # -------------------------------------------------------

  test "successive violations walk up the penalty ladder", %{pl: pl, ladder: ladder} do
    # First violation → strike 1, cooldown = 1_000
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Jump well past cooldown but well within the decay period (window_ms*10 = 10_000).
    Clock.advance(2_000)

    # Reoffend: fill the window again and trigger a second rejection.
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    assert {:error, :rate_limited, retry_after_2, 2} =
             PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Strike 2's cooldown is 5_000ms — retry_after should reflect that.
    assert retry_after_2 >= 5_000

    # Advance past cooldown 2, re-offend again.
    Clock.advance(6_000)

    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    assert {:error, :rate_limited, retry_after_3, 3} =
             PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Strike 3 → 30_000ms cooldown
    assert retry_after_3 >= 30_000
  end

  test "ladder clamps at the last entry for strikes beyond its length", %{pl: pl} do
    short_ladder = [1_000, 2_000]

    # Earn strike 1, wait for cooldown, earn strike 2, wait, earn strike 3.
    # Strike 3 should reuse the last ladder value (2_000), not crash.
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)

    Clock.advance(2_000)

    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)
    assert {:error, :rate_limited, _, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)

    Clock.advance(3_000)

    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)

    assert {:error, :rate_limited, retry_after, 3} =
             PenaltyLimiter.check(pl, "k", 3, 1_000, short_ladder)

    # Strike 3 reuses the last ladder entry: 2_000
    assert retry_after >= 2_000
    assert retry_after < 10_000
  end

  # -------------------------------------------------------
  # Strike decay
  # -------------------------------------------------------

  test "strikes decay after window_ms * 10 of good behavior", %{pl: pl, ladder: ladder} do
    # Earn one strike
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Decay period is window_ms * 10 = 10_000ms. Wait past it.
    Clock.advance(11_000)

    # Reoffend — strike count should be back to 1, not 2, since the previous strike decayed.
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    assert {:error, :rate_limited, _, 1} =
             PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end

  test "multiple strikes decay one at a time", %{pl: pl, ladder: ladder} do
    # Accumulate 3 strikes
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    Clock.advance(2_000)

    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    Clock.advance(6_000)

    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 3} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Wait exactly one decay period (10_000ms from last strike).
    Clock.advance(10_000)

    # Reoffend — should be strike 3 (one decayed, bringing 3 → 2, then +1 = 3).
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 3} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "strikes and cooldowns are per-key", %{pl: pl, ladder: ladder} do
    # Punish key "a"
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "a", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "a", 3, 1_000, ladder)

    # Key "b" should have a clean slate
    assert {:ok, 2} = PenaltyLimiter.check(pl, "b", 3, 1_000, ladder)
    assert {:ok, 1} = PenaltyLimiter.check(pl, "b", 3, 1_000, ladder)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "b", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "b", 3, 1_000, ladder)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "max_requests of 1 works with penalty ladder", %{pl: pl, ladder: ladder} do
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 1, 500, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 1, 500, ladder)
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "keys with no activity, no strikes, no cooldown are cleaned up", %{pl: pl, ladder: ladder} do
    # Populate keys whose windows then expire — they become indistinguishable
    # from never-seen keys and eligible for removal.
    for i <- 1..50 do
      assert {:ok, 0} = PenaltyLimiter.check(pl, "key:#{i}", 1, 100, ladder)
    end

    Clock.advance(200)
    send(pl, :cleanup)

    # Removal itself is deliberately invisible through the public API — a
    # removed key must behave exactly like a fresh one, and that equivalence
    # IS the contract. After the cleanup pass every expired key must present a
    # full fresh allowance, and the server must keep serving new keys.
    for i <- 1..50 do
      assert {:ok, 0} = PenaltyLimiter.check(pl, "key:#{i}", 1, 100, ladder)
    end

    assert {:ok, 0} = PenaltyLimiter.check(pl, "never_seen_key", 1, 100, ladder)
  end

  test "cleanup preserves in-window request history", %{pl: pl, ladder: ladder} do
    # Two of three window slots consumed, no strikes: the key is NOT inert, so
    # a cleanup pass must leave it alone. A cleanup that drops or trims live
    # keys would hand back a fresh allowance here.
    assert {:ok, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:ok, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    Clock.advance(100)
    send(pl, :cleanup)

    # Still the same window: exactly one slot left, then a rejection.
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end

  test "cleanup preserves active cooldowns and strike counts", %{pl: pl} do
    # TODO
  end

  test "an active cooldown is forgiven once a strike decays under it", %{pl: pl} do
    ladder = [1_000, 30_000]

    # Strike 1 at t=0 (cooldown 1_000ms).
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Past that cooldown, still inside the decay window: escalate to strike 2,
    # whose cooldown (30_000ms) far outlasts the decay period (10_000ms).
    Clock.advance(2_000)
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # One full decay period after strike 2: the cooldown (ending at t=32_000) is
    # still nominally active, but a strike has decayed, so it is cancelled and
    # the request is evaluated against the empty window instead of cooling_down.
    Clock.advance(10_000)
    assert {:ok, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Only one strike decayed (2 → 1, not a full reset), so re-offending
    # escalates straight back to strike 2.
    assert {:ok, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end

  test "a rejected request never occupies a window slot", %{pl: pl} do
    ladder = [1]

    # Three allowed requests at staggered times fill the window (max 3).
    assert {:ok, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    Clock.advance(100)
    assert {:ok, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    Clock.advance(100)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # A rejection at t=300 must NOT be stored as a window timestamp.
    Clock.advance(100)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Advance until only the first entry (t=0) has expired. Had the rejection
    # consumed a slot, the window would still be full and this would reject;
    # because it did not, exactly one fresh slot is available.
    Clock.advance(701)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end

  test "retry_after reflects window expiry when it exceeds the strike cooldown", %{pl: pl} do
    # The window (10_000ms) dwarfs the first-strike cooldown (1_000ms).
    ladder = [1_000]

    assert {:ok, 2} = PenaltyLimiter.check(pl, "k", 3, 10_000, ladder)
    assert {:ok, 1} = PenaltyLimiter.check(pl, "k", 3, 10_000, ladder)
    assert {:ok, 0} = PenaltyLimiter.check(pl, "k", 3, 10_000, ladder)

    # Oldest entry (t=0) expires at t=10_000; that 10_000ms window wait is larger
    # than the 1_000ms cooldown, so retry_after must be the window figure.
    assert {:error, :rate_limited, retry_after, 1} =
             PenaltyLimiter.check(pl, "k", 3, 10_000, ladder)

    assert retry_after == 10_000
  end

  test "the :name option registers the process for calls by name", %{ladder: ladder} do
    name = :penalty_limiter_named_process

    {:ok, _} =
      PenaltyLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity,
        name: name
      )

    assert {:ok, 0} = PenaltyLimiter.check(name, "k", 1, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(name, "k", 1, 1_000, ladder)
  end

  test "decay reference advances by a full period rather than resetting to now", %{
    pl: pl,
    ladder: ladder
  } do
    # Strike 1 at t=0.
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # Strike 2 at t=2_000 (last-strike reference = 2_000).
    Clock.advance(2_000)
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 2} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # t=17_000: 1.5 decay periods after the reference. Exactly one strike decays
    # (2 → 1) and the reference advances to t=12_000, NOT to t=17_000.
    Clock.advance(15_000)
    assert {:ok, _} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)

    # t=22_000: only 5_000ms since that check, but a full 10_000ms since the
    # advanced reference (12_000), so the last strike decays away and the key
    # resets. Re-offending therefore starts again at strike 1, not strike 2.
    Clock.advance(5_000)
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, ladder)
  end

  # -------------------------------------------------------
  # The periodic cleanup is driven by an automatically scheduled timer
  # -------------------------------------------------------

  test "the periodic cleanup timer fires and re-arms automatically" do
    test_pid = self()

    # Every cleanup pass reads the clock. This probe records each such call;
    # no other API call is issued after startup, so each tick is an automatic
    # sweep.
    clock = fn ->
      send(test_pid, :cleanup_clock_tick)
      0
    end

    {:ok, _pid} = PenaltyLimiter.start_link(clock: clock, cleanup_interval_ms: 25)

    # The first tick proves the startup timer fired; the second proves the pass
    # re-armed the next one, so the sweep repeats rather than running just once.
    # A scheduler that never arms Process.send_after would produce no ticks.
    assert_receive :cleanup_clock_tick, 1_000
    assert_receive :cleanup_clock_tick, 1_000
  end
end
```
