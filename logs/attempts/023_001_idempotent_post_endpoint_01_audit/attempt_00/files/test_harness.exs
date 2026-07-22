defmodule IdempotentPaymentsTest do
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

  @valid_params %{amount: 5000, currency: "USD", recipient: "merchant_42"}

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      IdempotentPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    %{pid: pid}
  end

  # -------------------------------------------------------
  # Basic payment processing (no idempotency key)
  # -------------------------------------------------------

  test "processes a payment and returns a response", %{pid: pid} do
    assert {:ok, resp} = IdempotentPayments.process_payment(pid, @valid_params)

    assert resp.amount == 5000
    assert resp.currency == "USD"
    assert resp.recipient == "merchant_42"
    assert resp.status == "completed"
    assert is_binary(resp.id)
    assert is_integer(resp.created_at)
  end

  test "requests without idempotency key always create new records", %{pid: pid} do
    {:ok, r1} = IdempotentPayments.process_payment(pid, @valid_params)
    {:ok, r2} = IdempotentPayments.process_payment(pid, @valid_params)

    assert r1.id != r2.id
    assert length(IdempotentPayments.get_payments(pid)) == 2
  end

  # -------------------------------------------------------
  # Idempotent behavior — duplicate key returns cached response
  # -------------------------------------------------------

  test "same idempotency key returns identical response without duplicate record", %{pid: pid} do
    key = "idem-abc-123"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)
    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # Responses must be byte-for-byte identical
    assert first == second

    # Only one payment record should exist
    assert length(IdempotentPayments.get_payments(pid)) == 1
  end

  test "cached response is returned even if params differ on replay", %{pid: pid} do
    key = "idem-lock"

    {:ok, first} =
      IdempotentPayments.process_payment(pid, @valid_params, key)

    # Second call with different amount — should still return original cached response
    {:ok, second} =
      IdempotentPayments.process_payment(
        pid,
        %{amount: 99_999, currency: "EUR", recipient: "someone_else"},
        key
      )

    assert first == second
    assert length(IdempotentPayments.get_payments(pid)) == 1
  end

  # -------------------------------------------------------
  # Different keys create different records
  # -------------------------------------------------------

  test "different idempotency keys create separate records", %{pid: pid} do
    {:ok, r1} = IdempotentPayments.process_payment(pid, @valid_params, "key-1")
    {:ok, r2} = IdempotentPayments.process_payment(pid, @valid_params, "key-2")

    assert r1.id != r2.id
    assert length(IdempotentPayments.get_payments(pid)) == 2
  end

  # -------------------------------------------------------
  # TTL expiry — expired key allows reprocessing
  # -------------------------------------------------------

  test "expired idempotency key allows reprocessing", %{pid: pid} do
    key = "idem-ttl"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # Advance past the TTL (10_000 ms configured in setup)
    Clock.advance(10_001)

    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # A new payment record should have been created
    assert first.id != second.id
    assert length(IdempotentPayments.get_payments(pid)) == 2
  end

  test "key is still valid just before expiry", %{pid: pid} do
    key = "idem-edge"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # Advance to just before TTL expires
    Clock.advance(9_999)

    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)

    assert first == second
    assert length(IdempotentPayments.get_payments(pid)) == 1
  end

  # -------------------------------------------------------
  # Invalid params
  # -------------------------------------------------------

  test "returns error for missing required fields", %{pid: pid} do
    assert {:error, :invalid_params} =
             IdempotentPayments.process_payment(pid, %{amount: 100})
  end

  test "error responses are also cached under idempotency key", %{pid: pid} do
    key = "idem-bad"

    result1 = IdempotentPayments.process_payment(pid, %{amount: 100}, key)
    result2 = IdempotentPayments.process_payment(pid, %{amount: 100}, key)

    assert result1 == {:error, :invalid_params}
    assert result2 == {:error, :invalid_params}

    # No payment records should have been created
    assert length(IdempotentPayments.get_payments(pid)) == 0
  end

  # -------------------------------------------------------
  # get_payment lookup
  # -------------------------------------------------------

  test "get_payment retrieves a specific record by id", %{pid: pid} do
    {:ok, resp} = IdempotentPayments.process_payment(pid, @valid_params)

    assert {:ok, found} = IdempotentPayments.get_payment(pid, resp.id)
    assert found.id == resp.id
    assert found.amount == 5000
  end

  test "get_payment returns error for unknown id", %{pid: pid} do
    assert {:error, :not_found} = IdempotentPayments.get_payment(pid, "pay_nonexistent")
  end

  # -------------------------------------------------------
  # Cleanup — expired idempotency entries are purged
  # -------------------------------------------------------

  test "cleanup removes expired idempotency entries but keeps payment records", %{pid: pid} do
    # Create 50 payments with unique idempotency keys
    for i <- 1..50 do
      IdempotentPayments.process_payment(pid, @valid_params, "batch-#{i}")
    end

    assert length(IdempotentPayments.get_payments(pid)) == 50

    # Advance past TTL
    Clock.advance(10_001)

    # Trigger the sweep manually via the documented :cleanup message
    send(pid, :cleanup)

    # A GenServer processes its mailbox in order, so the calls below also
    # confirm the sweep finished without crashing the server. Internal state
    # is implementation-dependent and deliberately not inspected; the
    # observable contract is that payment records survive cleanup while
    # expired idempotency keys do not.
    assert length(IdempotentPayments.get_payments(pid)) == 50

    # Idempotency keys are gone — replaying old keys creates new records
    # instead of returning cached responses
    {:ok, _resp} = IdempotentPayments.process_payment(pid, @valid_params, "batch-1")
    {:ok, _resp} = IdempotentPayments.process_payment(pid, @valid_params, "batch-50")
    assert length(IdempotentPayments.get_payments(pid)) == 52
    assert Process.alive?(pid)
  end

  # -------------------------------------------------------
  # Interleaved operations
  # -------------------------------------------------------

  test "interleaved idempotent and non-idempotent requests", %{pid: pid} do
    {:ok, r1} = IdempotentPayments.process_payment(pid, @valid_params, "key-A")
    {:ok, r2} = IdempotentPayments.process_payment(pid, @valid_params)
    {:ok, r3} = IdempotentPayments.process_payment(pid, @valid_params, "key-A")
    {:ok, r4} = IdempotentPayments.process_payment(pid, @valid_params)

    # r1 and r3 must be identical (same idempotency key)
    assert r1 == r3

    # r2 and r4 are independent new records
    assert r1.id != r2.id
    assert r2.id != r4.id

    # Total: r1 + r2 + r4 = 3 records (r3 is a cache hit)
    assert length(IdempotentPayments.get_payments(pid)) == 3
  end

  # -------------------------------------------------------
  # Deterministic IDs
  # -------------------------------------------------------

  test "payment IDs are unique and sequential", %{pid: pid} do
    {:ok, r1} = IdempotentPayments.process_payment(pid, @valid_params)
    {:ok, r2} = IdempotentPayments.process_payment(pid, @valid_params)
    {:ok, r3} = IdempotentPayments.process_payment(pid, @valid_params)

    ids = [r1.id, r2.id, r3.id]
    assert ids == Enum.uniq(ids)
  end

  test "cleanup keeps idempotency entries that have not expired yet", %{pid: pid} do
    {:ok, old_resp} = IdempotentPayments.process_payment(pid, @valid_params, "old-key")

    Clock.advance(6_000)
    {:ok, fresh_resp} = IdempotentPayments.process_payment(pid, @valid_params, "fresh-key")

    # now = 11_000: "old-key" expired at 10_000, "fresh-key" expires at 16_000
    Clock.advance(5_000)
    send(pid, :cleanup)

    # The unexpired entry must survive the sweep: replay is still a cache hit.
    assert {:ok, ^fresh_resp} =
             IdempotentPayments.process_payment(pid, @valid_params, "fresh-key")

    # The expired entry is gone: replay reprocesses into a brand new record.
    assert {:ok, replay} = IdempotentPayments.process_payment(pid, @valid_params, "old-key")
    assert replay.id != old_resp.id

    ids = pid |> IdempotentPayments.get_payments() |> Enum.map(& &1.id)
    assert length(ids) == 3
    assert old_resp.id in ids
    assert fresh_resp.id in ids
  end

  test "cached error replays even when the replay carries valid params", %{pid: pid} do
    key = "idem-error-then-valid"

    assert {:error, :invalid_params} =
             IdempotentPayments.process_payment(pid, %{amount: 100}, key)

    # Same key, now with fully valid params: the cached error must win, and no
    # payment record may be created.
    assert {:error, :invalid_params} =
             IdempotentPayments.process_payment(pid, @valid_params, key)

    assert IdempotentPayments.get_payments(pid) == []
  end

  test "response after expiry is re-cached under the same key with a fresh TTL", %{pid: pid} do
    key = "idem-recache"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)

    Clock.advance(10_001)
    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)
    assert second.id != first.id

    # The second response must now be cached for a full fresh TTL window.
    Clock.advance(9_999)
    assert {:ok, ^second} = IdempotentPayments.process_payment(pid, @valid_params, key)
    assert length(IdempotentPayments.get_payments(pid)) == 2
  end

  test "created_at is taken from the injected clock at processing time", %{pid: pid} do
    Clock.set(777_000)
    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params)
    assert first.created_at == 777_000

    Clock.set(1_234_567)
    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, "clock-key")
    assert second.created_at == 1_234_567

    assert {:ok, stored} = IdempotentPayments.get_payment(pid, second.id)
    assert stored.created_at == 1_234_567
  end

  test "default ttl_ms remembers idempotency keys for 24 hours", %{pid: _pid} do
    {:ok, server} =
      IdempotentPayments.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    {:ok, first} = IdempotentPayments.process_payment(server, @valid_params, "default-ttl")

    Clock.advance(86_399_999)

    assert {:ok, ^first} =
             IdempotentPayments.process_payment(server, @valid_params, "default-ttl")

    assert length(IdempotentPayments.get_payments(server)) == 1

    Clock.advance(2)
    {:ok, later} = IdempotentPayments.process_payment(server, @valid_params, "default-ttl")
    assert later.id != first.id
    assert length(IdempotentPayments.get_payments(server)) == 2
  end
end
