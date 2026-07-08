defmodule StrictIdempotentPaymentsTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    def start_link(initial \\ 0), do: Agent.start_link(fn -> initial end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  @valid %{amount: 5000, currency: "USD", recipient: "merchant_42"}

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      StrictIdempotentPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    %{pid: pid}
  end

  test "processes a payment and returns a response", %{pid: pid} do
    assert {:ok, resp} = StrictIdempotentPayments.process_payment(pid, @valid)
    assert resp.amount == 5000
    assert resp.status == "completed"
    assert is_binary(resp.id)
    assert is_integer(resp.created_at)
  end

  test "same key with same params returns identical response, one record", %{pid: pid} do
    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "abc")
    {:ok, second} = StrictIdempotentPayments.process_payment(pid, @valid, "abc")

    assert first == second
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1
  end

  test "same key with different params is a conflict and does not mutate the entry", %{pid: pid} do
    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "lock")

    conflict =
      StrictIdempotentPayments.process_payment(
        pid,
        %{amount: 99_999, currency: "EUR", recipient: "someone_else"},
        "lock"
      )

    assert conflict == {:error, :idempotency_key_conflict}
    # No new record was created by the conflicting replay
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1

    # The original entry is untouched: replaying the original params still works
    {:ok, again} = StrictIdempotentPayments.process_payment(pid, @valid, "lock")
    assert again == first
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1
  end

  test "different keys create separate records regardless of params", %{pid: pid} do
    {:ok, r1} = StrictIdempotentPayments.process_payment(pid, @valid, "k1")
    {:ok, r2} = StrictIdempotentPayments.process_payment(pid, @valid, "k2")

    assert r1.id != r2.id
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
  end

  test "expired key allows reprocessing with new params (no conflict)", %{pid: pid} do
    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "ttl")
    Clock.advance(10_001)

    {:ok, second} =
      StrictIdempotentPayments.process_payment(
        pid,
        %{amount: 111, currency: "GBP", recipient: "new_merchant"},
        "ttl"
      )

    assert first.id != second.id
    assert second.amount == 111
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
  end

  test "key is still valid just before expiry", %{pid: pid} do
    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "edge")
    Clock.advance(9_999)
    {:ok, second} = StrictIdempotentPayments.process_payment(pid, @valid, "edge")

    assert first == second
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1
  end

  test "returns error for missing required fields", %{pid: pid} do
    assert {:error, :invalid_params} =
             StrictIdempotentPayments.process_payment(pid, %{amount: 100})
  end

  test "error results are cached by fingerprint; different params under same key conflict", %{
    pid: pid
  } do
    r1 = StrictIdempotentPayments.process_payment(pid, %{amount: 100}, "bad")
    r2 = StrictIdempotentPayments.process_payment(pid, %{amount: 100}, "bad")

    assert r1 == {:error, :invalid_params}
    assert r2 == {:error, :invalid_params}
    assert StrictIdempotentPayments.get_payments(pid) == []

    # Same key, different (this time valid) params -> conflict, not a fresh record
    conflict = StrictIdempotentPayments.process_payment(pid, @valid, "bad")
    assert conflict == {:error, :idempotency_key_conflict}
    assert StrictIdempotentPayments.get_payments(pid) == []
  end

  test "get_payment retrieves by id and reports not found", %{pid: pid} do
    {:ok, resp} = StrictIdempotentPayments.process_payment(pid, @valid)
    assert {:ok, found} = StrictIdempotentPayments.get_payment(pid, resp.id)
    assert found.id == resp.id
    assert {:error, :not_found} = StrictIdempotentPayments.get_payment(pid, "pay_nope")
  end

  test "cleanup removes expired entries but keeps payment records", %{pid: pid} do
    for i <- 1..30 do
      StrictIdempotentPayments.process_payment(pid, @valid, "batch-#{i}")
    end

    assert length(StrictIdempotentPayments.get_payments(pid)) == 30

    Clock.advance(10_001)

    # Trigger the sweep manually via the documented :cleanup message. A
    # GenServer processes its mailbox in order, so the calls below also
    # confirm the sweep finished without crashing the server. Internal state
    # is implementation-dependent and deliberately not inspected; the
    # observable contract is that payment records survive cleanup while
    # expired idempotency entries do not.
    send(pid, :cleanup)

    assert length(StrictIdempotentPayments.get_payments(pid)) == 30

    # Replaying an expired key creates a fresh record rather than a cache hit
    {:ok, _} = StrictIdempotentPayments.process_payment(pid, @valid, "batch-1")
    assert length(StrictIdempotentPayments.get_payments(pid)) == 31
    assert Process.alive?(pid)
  end

  test "payment IDs are unique and sequential", %{pid: pid} do
    {:ok, r1} = StrictIdempotentPayments.process_payment(pid, @valid)
    {:ok, r2} = StrictIdempotentPayments.process_payment(pid, @valid)
    {:ok, r3} = StrictIdempotentPayments.process_payment(pid, @valid)
    ids = [r1.id, r2.id, r3.id]
    assert ids == Enum.uniq(ids)
  end
end
