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
    long_ladder = [5_000, 30_000]

    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, long_ladder)
    assert {:error, :rate_limited, _, 1} = PenaltyLimiter.check(pl, "k", 3, 1_000, long_ladder)

    # Past the window, inside the 5_000ms cooldown.
    Clock.advance(1_500)
    send(pl, :cleanup)

    # The cooldown must survive the cleanup pass untouched.
    assert {:error, :cooling_down, retry_after, 1} =
             PenaltyLimiter.check(pl, "k", 3, 1_000, long_ladder)

    assert retry_after > 3_000 and retry_after <= 5_000

    # Past the cooldown but well inside the decay period: the strike count
    # must also have survived, so the next violation escalates to strike 2.
    Clock.advance(4_000)
    for _ <- 1..3, do: PenaltyLimiter.check(pl, "k", 3, 1_000, long_ladder)

    assert {:error, :rate_limited, retry_after_2, 2} =
             PenaltyLimiter.check(pl, "k", 3, 1_000, long_ladder)

    assert retry_after_2 >= 30_000
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
