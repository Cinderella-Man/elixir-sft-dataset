defmodule LeaseBucketTest do
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
      LeaseBucket.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    %{lb: pid}
  end

  # -------------------------------------------------------
  # Basic acquire / release
  # -------------------------------------------------------

  test "acquire_lease reserves tokens and returns a lease id", %{lb: lb} do
    assert {:ok, lease_id, 7} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 60_000)
    assert is_reference(lease_id)

    assert {:ok, 1} = LeaseBucket.active_leases(lb, "k")
  end

  test "rejects acquire when tokens exceed free balance", %{lb: lb} do
    # Capacity 5, ask for 3 first
    assert {:ok, _, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    # Only 2 tokens free — a 3-token ask must be rejected
    assert {:error, :empty, retry_after} =
             LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    assert is_integer(retry_after)
    assert retry_after > 0
  end

  # -------------------------------------------------------
  # Release semantics — the defining behavior
  # -------------------------------------------------------

  test "release :cancelled refunds the tokens", %{lb: lb} do
    assert {:ok, lease_id, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", lease_id, :cancelled)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")

    # Full balance restored — can take another 5-token lease
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 5, 60_000)
  end

  test "release :completed keeps tokens consumed", %{lb: lb} do
    assert {:ok, lease_id, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", lease_id, :completed)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")

    # Balance is NOT refunded — only 2 tokens free
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)
    assert {:ok, _, 1} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 1, 60_000)
  end

  test "release of unknown lease returns {:error, :unknown_lease}", %{lb: lb} do
    # Unknown bucket
    assert {:error, :unknown_lease} =
             LeaseBucket.release(lb, "nope", make_ref(), :cancelled)

    # Known bucket, unknown lease
    LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 1, 60_000)

    assert {:error, :unknown_lease} =
             LeaseBucket.release(lb, "k", make_ref(), :cancelled)
  end

  test "double-release returns {:error, :unknown_lease} on second call", %{lb: lb} do
    {:ok, lease_id, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 2, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", lease_id, :cancelled)
    assert {:error, :unknown_lease} = LeaseBucket.release(lb, "k", lease_id, :cancelled)
  end

  # -------------------------------------------------------
  # Lease expiry — tokens are NOT refunded
  # -------------------------------------------------------

  test "expired leases disappear without refunding tokens", %{lb: lb} do
    # Acquire a lease with a 1-second timeout
    {:ok, lease_id, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 1_000)
    assert {:ok, 1} = LeaseBucket.active_leases(lb, "k")

    # Advance past lease expiry.  The next operation must expire the lease.
    Clock.advance(1_500)

    # active_leases triggers the expiry sweep for this bucket
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")

    # Explicitly releasing the expired lease should fail
    assert {:error, :unknown_lease} = LeaseBucket.release(lb, "k", lease_id, :cancelled)

    # Tokens are NOT refunded — but some will have refilled due to elapsed time.
    # At 1.0 tokens/sec with 1.5s elapsed, the free balance went from 2 to 3.5.
    # Acquiring 4 should still fail (only 3.5 free, floor = 3)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 4, 60_000)
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)
  end

  test "acquire/release trigger bucket-level expiry of OTHER leases", %{lb: lb} do
    # Short-timeout lease
    {:ok, _l1, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 500)

    # Long-timeout lease
    {:ok, l2, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 60_000)

    assert {:ok, 2} = LeaseBucket.active_leases(lb, "k")

    # Advance past the short lease's expiry but within the long lease's
    Clock.advance(1_000)

    # Any operation should expire the short lease
    assert :ok = LeaseBucket.release(lb, "k", l2, :completed)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")
  end

  # -------------------------------------------------------
  # Refill math (standard token bucket, on the free balance)
  # -------------------------------------------------------

  test "free balance refills lazily between calls", %{lb: lb} do
    # Drain to 0 by acquiring and then never releasing
    {:ok, _lease, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 5, 60_000)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 1, 60_000)

    # Advance 2 seconds at 1 token/sec — free balance goes from 0 to 2
    Clock.advance(2_000)

    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 2, 60_000)
  end

  test "refill caps at capacity", %{lb: lb} do
    # Acquire and cancel to leave bucket intact at full
    {:ok, l, _} = LeaseBucket.acquire_lease(lb, "k", 3, 1.0, 3, 60_000)
    LeaseBucket.release(lb, "k", l, :cancelled)

    # Idle for a long time — balance should cap at 3, not accumulate
    Clock.advance(100_000)

    # Should still only admit 3, not more
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 3, 1.0, 3, 60_000)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 3, 1.0, 1, 60_000)
  end

  # -------------------------------------------------------
  # Multiple concurrent leases on the same bucket
  # -------------------------------------------------------

  test "multiple outstanding leases are tracked independently", %{lb: lb} do
    {:ok, l1, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 60_000)
    {:ok, l2, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 4, 60_000)
    {:ok, l3, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 2, 60_000)

    assert {:ok, 3} = LeaseBucket.active_leases(lb, "k")

    # Cancelling l2 refunds 4 tokens
    assert :ok = LeaseBucket.release(lb, "k", l2, :cancelled)
    assert {:ok, 2} = LeaseBucket.active_leases(lb, "k")

    # 4 tokens refunded + 1 still free = 5 free
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 5, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", l1, :completed)
    assert :ok = LeaseBucket.release(lb, "k", l3, :cancelled)
  end

  # -------------------------------------------------------
  # Bucket independence
  # -------------------------------------------------------

  test "different buckets are completely isolated", %{lb: lb} do
    {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "a", 3, 1.0, 3, 60_000)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "a", 3, 1.0, 1, 60_000)

    # Bucket "b" is untouched
    assert {:ok, _, 2} = LeaseBucket.acquire_lease(lb, "b", 3, 1.0, 1, 60_000)
    assert {:ok, _, 1} = LeaseBucket.acquire_lease(lb, "b", 3, 1.0, 1, 60_000)
  end

  # -------------------------------------------------------
  # active_leases on unknown bucket
  # -------------------------------------------------------

  test "active_leases returns 0 for unknown bucket", %{lb: lb} do
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "never_seen")
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "cleanup drops fully-refilled buckets with no active leases", %{lb: lb} do
    # Create 50 buckets, each with one short lease that will expire
    for i <- 1..50 do
      LeaseBucket.acquire_lease(lb, "k:#{i}", 2, 10.0, 2, 100)
    end

    # Advance far enough for leases to expire AND buckets to refill
    Clock.advance(10_000)

    send(lb, :cleanup)
    :sys.get_state(lb)

    state = :sys.get_state(lb)
    assert map_size(state.buckets) == 0
  end

  test "cleanup keeps buckets with active leases", %{lb: lb} do
    # Long-running lease keeps the bucket alive
    {:ok, _l, _} = LeaseBucket.acquire_lease(lb, "alive", 5, 1.0, 2, 3_600_000)

    # Short lease expires
    LeaseBucket.acquire_lease(lb, "gone", 2, 10.0, 1, 100)
    Clock.advance(10_000)

    send(lb, :cleanup)
    :sys.get_state(lb)

    state = :sys.get_state(lb)
    assert Map.has_key?(state.buckets, "alive")
    refute Map.has_key?(state.buckets, "gone")
  end
end
