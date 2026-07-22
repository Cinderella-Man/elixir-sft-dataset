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

    # A synchronous call is served only after the cleanup message is handled,
    # so this both waits for the sweep and reads an untouched bucket name.
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "sentinel")

    # A swept bucket is indistinguishable from a fresh one: no active leases
    # and a free balance back at full capacity.
    for i <- 1..50 do
      assert {:ok, 0} = LeaseBucket.active_leases(lb, "k:#{i}")
      assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k:#{i}", 2, 10.0, 2, 100)
    end
  end

  test "cleanup keeps buckets with active leases", %{lb: lb} do
    # Long-running lease keeps the bucket alive
    {:ok, l, _} = LeaseBucket.acquire_lease(lb, "alive", 5, 1.0, 2, 3_600_000)

    # Short lease expires
    LeaseBucket.acquire_lease(lb, "gone", 2, 10.0, 1, 100)
    Clock.advance(10_000)

    send(lb, :cleanup)

    # A synchronous call is served only after the cleanup message is handled.
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "sentinel")

    # The long lease survived the sweep: it is still counted and still
    # releasable by its id.
    assert {:ok, 1} = LeaseBucket.active_leases(lb, "alive")
    assert :ok = LeaseBucket.release(lb, "alive", l, :completed)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "alive")

    # The bucket whose only lease expired is back to fresh behavior.
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "gone")
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "gone", 2, 10.0, 2, 100)
  end

  test "start_link registers the process under the :name option" do
    name = :lease_bucket_named_test

    {:ok, _pid} =
      LeaseBucket.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity,
        name: name
      )

    assert {:ok, lease_id, 2} = LeaseBucket.acquire_lease(name, "k", 5, 1.0, 3, 60_000)
    assert is_reference(lease_id)
    assert {:ok, 1} = LeaseBucket.active_leases(name, "k")
  end

  test "lease ids are unique across different buckets", %{lb: lb} do
    {:ok, l1, _} = LeaseBucket.acquire_lease(lb, "a", 5, 1.0, 1, 60_000)
    {:ok, l2, _} = LeaseBucket.acquire_lease(lb, "b", 5, 1.0, 1, 60_000)

    assert is_reference(l1) and is_reference(l2)
    assert l1 != l2
  end

  # -------------------------------------------------------
  # retry_after is the EXACT time to refill the deficit
  #
  # These pin the documented formula
  #   retry_after = ceil((tokens - free) * 1000 / refill_rate)
  # so any change to the subtraction, the *1000 factor, or the 1000
  # constant is observable through the public {:error, :empty, n} reply.
  # -------------------------------------------------------

  test "retry_after equals the exact ms needed to refill the deficit", %{lb: lb} do
    # capacity 5, refill 1.0 tok/s.  Reserve 3, leaving 2 free.
    assert {:ok, _l, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    # No time elapses, so 2 tokens are free and we ask for 3: deficit is 1
    # token, which at 1 tok/s takes exactly 1000 ms to refill.
    assert {:error, :empty, 1000} =
             LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)
  end

  test "retry_after rounds the fractional refill time up", %{lb: lb} do
    # capacity 5, refill 3.0 tok/s.  Reserve 4, leaving 1 free.
    assert {:ok, _l, 1} = LeaseBucket.acquire_lease(lb, "k", 5, 3.0, 4, 60_000)

    # Ask for 3 with only 1 free: deficit of 2 tokens at 3 tok/s is 666.66 ms,
    # which must round UP to 667.
    assert {:error, :empty, 667} =
             LeaseBucket.acquire_lease(lb, "k", 5, 3.0, 3, 60_000)
  end

  # -------------------------------------------------------
  # Argument boundaries: the smallest legal values are accepted,
  # and non-positive values are rejected by the guards.
  # -------------------------------------------------------

  test "a capacity-1 / 1-token lease is accepted", %{lb: lb} do
    assert {:ok, lease_id, 0} = LeaseBucket.acquire_lease(lb, "one", 1, 1.0, 1, 60_000)
    assert is_reference(lease_id)
    assert {:ok, 1} = LeaseBucket.active_leases(lb, "one")
  end

  test "a 1-ms lease timeout is accepted", %{lb: lb} do
    assert {:ok, _l, 4} = LeaseBucket.acquire_lease(lb, "t", 5, 1.0, 1, 1)
  end

  test "non-positive arguments are rejected by the guards", %{lb: lb} do
    # refill_rate must be strictly positive
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 5, 0.0, 3, 60_000)
    end

    # tokens must be strictly positive
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 0, 60_000)
    end

    # lease_timeout_ms must be strictly positive
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 0)
    end
  end

  # -------------------------------------------------------
  # Expiry boundary: expires_at <= now (inclusive), not strictly <.
  # -------------------------------------------------------

  test "a lease expires exactly at its deadline (expires_at == now)", %{lb: lb} do
    {:ok, _l, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 1_000)
    assert {:ok, 1} = LeaseBucket.active_leases(lb, "k")

    # Advance to EXACTLY the expiry instant.  expires_at (1000) <= now (1000),
    # so the lease must be treated as expired.
    Clock.advance(1_000)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")
  end
end
