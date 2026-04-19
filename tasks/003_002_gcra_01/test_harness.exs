defmodule GcraLimiterTest do
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
    start_supervised!({Clock, 0})

    {:ok, pid} =
      GcraLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    %{gl: pid}
  end

  # -------------------------------------------------------
  # Fresh bucket admits the full burst immediately
  # -------------------------------------------------------

  test "a brand-new bucket admits the configured burst back-to-back", %{gl: gl} do
    # 5 req/sec, burst of 5 — should admit 5 instantly
    assert {:ok, 4} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 3} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 2} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  test "rejects once the burst is exhausted", %{gl: gl} do
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "k", 5.0, 5)

    assert {:error, :rate_exceeded, retry_after} =
             GcraLimiter.acquire(gl, "k", 5.0, 5)

    assert is_integer(retry_after)
    assert retry_after > 0
    # At 5 req/sec, emission interval = 200ms, so we shouldn't wait more than that
    # to admit one more after a full burst at t=0.
    assert retry_after <= 200
  end

  # -------------------------------------------------------
  # Steady-state rate (after burst is consumed)
  # -------------------------------------------------------

  test "admits at the steady-state rate after burst is exhausted", %{gl: gl} do
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)

    # After one emission interval (200ms), one more is admitted.
    Clock.advance(200)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)

    # Two more intervals → two more admits.
    Clock.advance(400)
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  # -------------------------------------------------------
  # The max(now, tat) trap — idle buckets don't accrue unbounded credit
  # -------------------------------------------------------

  test "long idle does not credit the bucket beyond burst size", %{gl: gl} do
    # Consume a few, then idle for a very long time.
    for _ <- 1..3, do: GcraLimiter.acquire(gl, "k", 5.0, 5)
    Clock.advance(10_000_000)

    # We should admit exactly `burst` requests back-to-back — the million
    # milliseconds of idle time must not translate to a million-request burst.
    assert {:ok, 4} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 3} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 2} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  # -------------------------------------------------------
  # The "don't advance TAT on rejection" trap
  # -------------------------------------------------------

  test "repeated rejects do not push future admits further away", %{gl: gl} do
    # Burn through the burst at t=0
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "k", 5.0, 5)

    # Spam rejections — TAT must not advance with each one
    for _ <- 1..50, do: GcraLimiter.acquire(gl, "k", 5.0, 5)

    # After exactly one emission interval (200ms), we must still be able to
    # admit one.  If the implementation naively updated TAT on every reject,
    # the admit frontier would be 50 emission intervals into the future.
    Clock.advance(200)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  # -------------------------------------------------------
  # Bucket independence
  # -------------------------------------------------------

  test "different buckets maintain independent TATs", %{gl: gl} do
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "a", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "a", 5.0, 5)

    # Bucket "b" has not been touched
    assert {:ok, 4} = GcraLimiter.acquire(gl, "b", 5.0, 5)
    assert {:ok, 3} = GcraLimiter.acquire(gl, "b", 5.0, 5)
  end

  # -------------------------------------------------------
  # Multi-token acquires
  # -------------------------------------------------------

  test "consuming multiple tokens at once deducts all of them", %{gl: gl} do
    # Burst of 5; take 3 in one call
    assert {:ok, 2} = GcraLimiter.acquire(gl, "k", 5.0, 5, 3)

    # Only 2 single-token acquires left in the burst
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  test "multi-token acquire that exceeds burst is rejected", %{gl: gl} do
    # Burst of 5; asking for 6 at once must be rejected
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5, 6)

    # And rejection must not have mutated TAT — the full burst is still available
    assert {:ok, 4} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  # -------------------------------------------------------
  # retry_after accuracy
  # -------------------------------------------------------

  test "retry_after reports time until the earliest admit", %{gl: gl} do
    # Consume full burst at t=0
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "k", 5.0, 5)

    # At t=0 the next admit is at t=200 (one emission interval)
    assert {:error, :rate_exceeded, retry_after} =
             GcraLimiter.acquire(gl, "k", 5.0, 5)

    assert retry_after >= 1 and retry_after <= 200

    # At t=100, retry_after should be ~100
    Clock.advance(100)

    assert {:error, :rate_exceeded, retry_after_2} =
             GcraLimiter.acquire(gl, "k", 5.0, 5)

    assert retry_after_2 >= 1 and retry_after_2 <= 100
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "idle buckets are dropped by cleanup" do
    # Removed the redundant `start_supervised!({Clock, 0})` here

    {:ok, pid} =
      GcraLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity,
        cleanup_idle_ms: 1_000
      )

    # Touch 100 buckets
    for i <- 1..100, do: GcraLimiter.acquire(pid, "k:#{i}", 5.0, 5)

    # Advance well past cleanup_idle_ms
    Clock.advance(2_000)

    send(pid, :cleanup)
    :sys.get_state(pid)

    state = :sys.get_state(pid)
    assert map_size(state.buckets) == 0

    # Fresh bucket after cleanup behaves like new
    assert {:ok, 4} = GcraLimiter.acquire(pid, "k:1", 5.0, 5)
  end

  # -------------------------------------------------------
  # Fractional rates
  # -------------------------------------------------------

  test "works with fractional rates (e.g. 0.5 req/sec)", %{gl: gl} do
    # 0.5 req/sec → emission_interval = 2000ms, burst of 2
    assert {:ok, 1} = GcraLimiter.acquire(gl, "slow", 0.5, 2)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "slow", 0.5, 2)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "slow", 0.5, 2)

    # After 2 seconds, one more is admitted
    Clock.advance(2_000)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "slow", 0.5, 2)
  end
end
