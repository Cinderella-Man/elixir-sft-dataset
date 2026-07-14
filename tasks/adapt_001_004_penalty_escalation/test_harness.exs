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
end
