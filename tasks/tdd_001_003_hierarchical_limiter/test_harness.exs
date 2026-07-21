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
      assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "key:#{i}", tiers)
    end

    # While the window is live, every key is holding its single slot.
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "key:1", tiers)

    # Advance past the widest window so every recorded timestamp is expired.
    Clock.advance(200)

    send(hl, :cleanup)

    # The next check is a synchronous call, so it can only be served after the
    # cleanup pass has run. Every key admits a fresh request with a full
    # allowance, showing no expired timestamp survived the sweep.
    assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "key:1", tiers)

    for i <- 2..100 do
      assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "key:#{i}", tiers)
    end

    # The freshly recorded timestamps are honoured — the swept keys start over
    # rather than staying permanently open.
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "key:50", tiers)
  end

  test "cleanup keeps entries within the widest window ever seen for a key", %{hl: hl} do
    wide = [{:hour, 5, 3_600_000}]
    narrow = [{:sec, 5, 1_000}]

    # t=0: record one timestamp while the widest window seen is 1 hour.
    assert {:ok, %{hour: 4}} = HierarchicalLimiter.check(hl, "k", wide)

    # t=500: a narrow check still sees the t=0 entry (0.5s old) and records another.
    Clock.advance(500)
    assert {:ok, %{sec: 3}} = HierarchicalLimiter.check(hl, "k", narrow)

    # t=1600: both entries are ~1s old — far inside the widest window seen (1 hour),
    # so a cleanup pass must retain them rather than pruning to the 1s window.
    Clock.advance(1_100)
    send(hl, :cleanup)

    # The hour tier must still count both retained timestamps: 2 used + 1 new, so
    # remaining is 5 - 2 - 1 = 2. If cleanup wrongly pruned to the 1s window the
    # key would be dropped and this would report hour: 4.
    assert {:ok, %{hour: 2}} = HierarchicalLimiter.check(hl, "k", wide)
  end

  test "check reaches the process through the registered :name" do
    name = :hierarchical_limiter_named_server

    {:ok, _pid} =
      HierarchicalLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity,
        name: name
      )

    tiers = [{:per_sec, 1, 1_000}]
    assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(name, "k", tiers)
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(name, "k", tiers)
  end

  test "retry_after actually elapses to an admitted request", %{hl: hl} do
    wide = [{:t, 5, 1_000}]

    # Fill the shared timestamp list with 5 staggered entries (t = 0,100,..,400).
    assert {:ok, %{t: 4}} = HierarchicalLimiter.check(hl, "k", wide)
    Clock.advance(100)
    assert {:ok, %{t: 3}} = HierarchicalLimiter.check(hl, "k", wide)
    Clock.advance(100)
    assert {:ok, %{t: 2}} = HierarchicalLimiter.check(hl, "k", wide)
    Clock.advance(100)
    assert {:ok, %{t: 1}} = HierarchicalLimiter.check(hl, "k", wide)
    Clock.advance(100)
    assert {:ok, %{t: 0}} = HierarchicalLimiter.check(hl, "k", wide)

    # Same shared list, now evaluated against a tighter cap of 2 (4 entries over).
    narrow = [{:t, 2, 1_000}]

    assert {:error, :rate_limited, :t, retry} =
             HierarchicalLimiter.check(hl, "k", narrow)

    # The contract fixes retry as the wait until this tier admits a new request.
    # After exactly that wait the tier must accept — waiting only for the single
    # oldest entry to expire (retry = 600) leaves the tier still saturated.
    Clock.advance(retry)
    assert {:ok, _} = HierarchicalLimiter.check(hl, "k", narrow)
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

    {:ok, _pid} = HierarchicalLimiter.start_link(clock: clock, cleanup_interval_ms: 25)

    # The first tick proves the startup timer fired; the second proves the pass
    # re-armed the next one, so the sweep repeats rather than running just once.
    # A scheduler that never arms Process.send_after would produce no ticks.
    assert_receive :cleanup_clock_tick, 1_000
    assert_receive :cleanup_clock_tick, 1_000
  end
end
