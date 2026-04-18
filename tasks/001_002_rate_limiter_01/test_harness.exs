defmodule FixedWindowLimiterTest do
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
      FixedWindowLimiter.start_link(
        clock: &Clock.now/0,
        # disable auto-cleanup in tests
        cleanup_interval_ms: :infinity
      )

    %{fw: pid}
  end

  # -------------------------------------------------------
  # Basic allow / reject
  # -------------------------------------------------------

  test "allows requests up to the limit within a window", %{fw: fw} do
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "user:1", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "user:1", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "user:1", 3, 1_000)
  end

  test "rejects requests past the limit within a window", %{fw: fw} do
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)

    assert {:error, :rate_limited, retry_after} =
             FixedWindowLimiter.check(fw, "k", 3, 1_000)

    assert is_integer(retry_after)
    assert retry_after > 0
    assert retry_after <= 1_000
  end

  # -------------------------------------------------------
  # Window reset behaviour (the defining property)
  # -------------------------------------------------------

  test "counter resets abruptly at window boundary", %{fw: fw} do
    # Fill up window 0 (t=0..999)
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Cross into window 1 (t=1000..1999). Counter resets.
    Clock.set(1_000)
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
  end

  test "boundary burst is allowed (known property of fixed windows)", %{fw: fw} do
    # Fill window 0 at t=999 — the very end of the window
    Clock.set(999)
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Jump 1ms forward into window 1 — fresh counter, full allowance
    Clock.set(1_000)
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # 6 requests within 1ms of wall-clock time — the well-known
    # fixed-window-boundary burst. This is accepted by this implementation.
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
  end

  test "requests mid-window don't reset the counter", %{fw: fw} do
    # t=0: first request
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=400: second request (still in window 0)
    Clock.advance(400)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=800: third request (still in window 0)
    Clock.advance(400)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=800: fourth request — rejected, counter at 3
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=999: still in window 0, still rejected
    Clock.set(999)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "different keys are completely independent", %{fw: fw} do
    # Exhaust key "a"
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "a", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "a", 3, 1_000)

    # Key "b" should be unaffected
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "b", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "b", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "b", 3, 1_000)
  end

  # -------------------------------------------------------
  # retry_after accuracy
  # -------------------------------------------------------

  test "retry_after reports time until window ends", %{fw: fw} do
    # Fill window 0 at t=0
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Advance to t=300
    Clock.advance(300)

    assert {:error, :rate_limited, retry_after} =
             FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Window 0 ends at t=1000. We're at t=300, so retry_after should be 700.
    assert retry_after == 700
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "max_requests of 1 allows exactly one call per window", %{fw: fw} do
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 500)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 1, 500)

    # Next window starts at t=500
    Clock.set(500)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 500)
  end

  test "works with very large window", %{fw: fw} do
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 86_400_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 1, 86_400_000)

    # Next day's window
    Clock.set(86_400_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 86_400_000)
  end

  # -------------------------------------------------------
  # Multiple keys interleaved
  # -------------------------------------------------------

  test "interleaved operations on multiple keys", %{fw: fw} do
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "x", 2, 1_000)
    assert {:ok, 4} = FixedWindowLimiter.check(fw, "y", 5, 2_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "x", 2, 1_000)
    assert {:ok, 3} = FixedWindowLimiter.check(fw, "y", 5, 2_000)

    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "x", 2, 1_000)
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "y", 5, 2_000)
  end

  # -------------------------------------------------------
  # Cleanup (memory leak prevention)
  # -------------------------------------------------------

  test "expired window counters are cleaned up and don't accumulate", %{fw: fw} do
    # Create counter entries for 100 different keys in window 0 (t=0, window_ms=100)
    for i <- 1..100 do
      FixedWindowLimiter.check(fw, "key:#{i}", 1, 100)
    end

    # Advance past the window end (window 0 ends at t=100)
    Clock.advance(200)

    # Trigger cleanup manually via a message
    # The GenServer should handle a :cleanup message
    send(fw, :cleanup)
    # Give it a moment to process
    :sys.get_state(fw)

    # Now the internal state should not hold 100 counter entries
    state = :sys.get_state(fw)
    assert map_size(state.counters) == 0

    # New requests for those keys should work fresh in the new window
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "key:1", 1, 100)
  end
end
