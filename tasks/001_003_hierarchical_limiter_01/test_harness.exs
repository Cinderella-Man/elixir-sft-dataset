defmodule HierarchicalLimiterTest do
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
      HierarchicalLimiter.start_link(
        clock: &Clock.now/0,
        # disable auto-cleanup in tests
        cleanup_interval_ms: :infinity
      )

    %{hl: pid}
  end

  # -------------------------------------------------------
  # Single-tier behaviour (should match sliding window)
  # -------------------------------------------------------

  test "with a single tier, behaves like a sliding window limiter", %{hl: hl} do
    tiers = [{:per_sec, 3, 1_000}]

    assert {:ok, %{per_sec: 2}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:ok, %{per_sec: 1}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)
  end

  # -------------------------------------------------------
  # Multi-tier: all must pass
  # -------------------------------------------------------

  test "request is allowed only when every tier has capacity", %{hl: hl} do
    tiers = [{:per_sec, 5, 1_000}, {:per_min, 10, 60_000}]

    # Burn through the per_sec tier (5 requests at t=0).
    for _ <- 1..5, do: HierarchicalLimiter.check(hl, "k", tiers)

    # 6th request is rejected by per_sec even though per_min still has headroom.
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)

    # Advance to t=1001, per_sec clears, per_min still holds 5 of 10.
    Clock.advance(1_001)
    assert {:ok, %{per_sec: 4, per_min: 4}} = HierarchicalLimiter.check(hl, "k", tiers)
  end

  test "tighter outer tier can reject even when inner tier has capacity", %{hl: hl} do
    # 10/sec AND 15/min — the minute cap is the binding constraint across bursts.
    tiers = [{:per_sec, 10, 1_000}, {:per_min, 15, 60_000}]

    # 10 requests in the first second
    for _ <- 1..10, do: HierarchicalLimiter.check(hl, "k", tiers)

    # Advance 1.5 seconds: per_sec is clear, per_min has 10 and allows 5 more.
    Clock.advance(1_500)
    for _ <- 1..5, do: HierarchicalLimiter.check(hl, "k", tiers)

    # 16th request: per_sec has headroom but per_min is full → rejected by per_min.
    assert {:error, :rate_limited, :per_min, _} = HierarchicalLimiter.check(hl, "k", tiers)
  end

  test "rejected requests do not consume budget on any tier", %{hl: hl} do
    tiers = [{:per_sec, 2, 1_000}, {:per_min, 10, 60_000}]

    assert {:ok, %{per_sec: 1, per_min: 9}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:ok, %{per_sec: 0, per_min: 8}} = HierarchicalLimiter.check(hl, "k", tiers)

    # Blast a bunch of rejections against per_sec.
    for _ <- 1..10 do
      assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)
    end

    # Advance past the per_sec window. per_min must show only 2 consumed,
    # not 12 — rejections shouldn't count.
    Clock.advance(1_001)
    assert {:ok, %{per_min: 7}} = HierarchicalLimiter.check(hl, "k", tiers)
  end

  # -------------------------------------------------------
  # Tightest-tier reporting
  # -------------------------------------------------------

  test "reports the tier with the longest retry_after when multiple fail", %{hl: hl} do
    # Both tiers will saturate simultaneously at t=0.
    tiers = [{:per_sec, 3, 1_000}, {:per_min, 3, 60_000}]

    for _ <- 1..3, do: HierarchicalLimiter.check(hl, "k", tiers)

    # Both tiers are at their limit. per_min's retry_after is ~60_000;
    # per_sec's is ~1_000. The caller has to wait on per_min.
    assert {:error, :rate_limited, :per_min, retry_after} =
             HierarchicalLimiter.check(hl, "k", tiers)

    assert retry_after > 1_000
    assert retry_after <= 60_000
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "different keys have independent budgets across all tiers", %{hl: hl} do
    tiers = [{:per_sec, 2, 1_000}, {:per_min, 5, 60_000}]

    # Exhaust per_sec for "a"
    HierarchicalLimiter.check(hl, "a", tiers)
    HierarchicalLimiter.check(hl, "a", tiers)
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "a", tiers)

    # "b" is unaffected
    assert {:ok, %{per_sec: 1, per_min: 4}} = HierarchicalLimiter.check(hl, "b", tiers)
    assert {:ok, %{per_sec: 0, per_min: 3}} = HierarchicalLimiter.check(hl, "b", tiers)
  end

  # -------------------------------------------------------
  # retry_after accuracy per tier
  # -------------------------------------------------------

  test "retry_after tracks the blocking tier's oldest-entry expiry", %{hl: hl} do
    tiers = [{:per_sec, 1, 1_000}]

    HierarchicalLimiter.check(hl, "k", tiers)
    Clock.advance(300)

    assert {:error, :rate_limited, :per_sec, retry_after} =
             HierarchicalLimiter.check(hl, "k", tiers)

    # Oldest (and only) entry is at t=0, expires at t=1000. We're at t=300.
    assert retry_after >= 600 and retry_after <= 800
  end

  # -------------------------------------------------------
  # Three-tier stack: the motivating real-world case
  # -------------------------------------------------------

  test "three-tier stack admits a sustainable request rate", %{hl: hl} do
    tiers = [
      {:per_sec, 10, 1_000},
      {:per_min, 100, 60_000},
      {:per_hour, 1_000, 3_600_000}
    ]

    # 10 requests at t=0 — saturates per_sec.
    for _ <- 1..10, do: HierarchicalLimiter.check(hl, "k", tiers)
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)

    # Advance a second, fire 10 more. Still under per_min (20/100) and per_hour (20/1000).
    Clock.advance(1_001)

    for i <- 1..10 do
      assert {:ok, remaining} = HierarchicalLimiter.check(hl, "k", tiers)
      assert remaining.per_sec == 10 - i
    end
  end

  # -------------------------------------------------------
  # Cleanup (memory leak prevention)
  # -------------------------------------------------------

  test "expired entries are pruned and empty keys dropped", %{hl: hl} do
    tiers = [{:per_sec, 1, 100}]

    for i <- 1..100 do
      HierarchicalLimiter.check(hl, "key:#{i}", tiers)
    end

    # Advance past the widest window
    Clock.advance(200)

    send(hl, :cleanup)
    :sys.get_state(hl)

    state = :sys.get_state(hl)
    assert map_size(state.keys) == 0

    # New requests work fresh
    assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "key:1", tiers)
  end
end
