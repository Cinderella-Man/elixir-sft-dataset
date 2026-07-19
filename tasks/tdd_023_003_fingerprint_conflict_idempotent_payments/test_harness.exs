defmodule StrictIdempotentPaymentsTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    def start_link(initial \\ 0), do: Agent.start_link(fn -> initial end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
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

  test "same key, different params conflicts and leaves entry unchanged", %{pid: pid} do
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

  test "key is expired exactly at the ttl boundary", %{pid: pid} do
    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "boundary")

    # Entry expiry is 0 + ttl_ms (10_000): at exactly 10_000 the TTL has elapsed,
    # so the replay must be processed fresh rather than served from the cache.
    Clock.advance(10_000)
    {:ok, second} = StrictIdempotentPayments.process_payment(pid, @valid, "boundary")

    assert second.id != first.id
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
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

  test "payment IDs are counter-based and start at pay_1", %{pid: pid} do
    {:ok, r1} = StrictIdempotentPayments.process_payment(pid, @valid)
    {:ok, r2} = StrictIdempotentPayments.process_payment(pid, @valid, "counted")
    {:ok, r3} = StrictIdempotentPayments.process_payment(pid, @valid)

    assert r1.id == "pay_1"
    assert r2.id == "pay_2"
    assert r3.id == "pay_3"

    assert {:ok, %{id: "pay_1"}} = StrictIdempotentPayments.get_payment(pid, "pay_1")
    assert {:ok, %{id: "pay_3"}} = StrictIdempotentPayments.get_payment(pid, "pay_3")
    assert {:error, :not_found} = StrictIdempotentPayments.get_payment(pid, "pay_4")

    assert Enum.map(StrictIdempotentPayments.get_payments(pid), & &1.id) ==
             ["pay_1", "pay_2", "pay_3"]
  end

  test "get_payments lists records in creation order, oldest first", %{pid: pid} do
    {:ok, r1} = StrictIdempotentPayments.process_payment(pid, @valid, "o1")
    Clock.advance(5)
    {:ok, r2} = StrictIdempotentPayments.process_payment(pid, @valid, "o2")
    Clock.advance(5)
    {:ok, r3} = StrictIdempotentPayments.process_payment(pid, @valid, "o3")

    ids = Enum.map(StrictIdempotentPayments.get_payments(pid), & &1.id)
    assert ids == [r1.id, r2.id, r3.id]
  end

  test "ttl_ms defaults to 86,400,000 ms when the option is omitted" do
    {:ok, pid} =
      StrictIdempotentPayments.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "dflt")

    Clock.advance(86_399_999)
    {:ok, cached} = StrictIdempotentPayments.process_payment(pid, @valid, "dflt")
    assert cached == first
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1

    Clock.advance(2)
    {:ok, fresh} = StrictIdempotentPayments.process_payment(pid, @valid, "dflt")
    assert fresh.id != first.id
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
  end

  test "nil key creates a new record on every call even with identical params", %{pid: pid} do
    {:ok, r1} = StrictIdempotentPayments.process_payment(pid, @valid)
    {:ok, r2} = StrictIdempotentPayments.process_payment(pid, @valid, nil)

    assert r1.id != r2.id
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
    assert {:ok, _} = StrictIdempotentPayments.get_payment(pid, r1.id)
    assert {:ok, _} = StrictIdempotentPayments.get_payment(pid, r2.id)
  end

  test "cleanup keeps unexpired entries while purging expired ones", %{pid: pid} do
    {:ok, old} = StrictIdempotentPayments.process_payment(pid, @valid, "old-key")
    Clock.advance(6_000)
    {:ok, fresh} = StrictIdempotentPayments.process_payment(pid, @valid, "fresh-key")
    Clock.advance(5_000)

    send(pid, :cleanup)

    # "fresh-key" expires at 16_000 and is still live at 11_000: cache hit.
    {:ok, replay} = StrictIdempotentPayments.process_payment(pid, @valid, "fresh-key")
    assert replay == fresh
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2

    # "old-key" expired at 10_000 and was purged: reprocessed fresh.
    {:ok, again} = StrictIdempotentPayments.process_payment(pid, @valid, "old-key")
    assert again.id != old.id
    assert length(StrictIdempotentPayments.get_payments(pid)) == 3
  end

  test "cleanup purges an entry whose expiry has been reached exactly", %{pid: pid} do
    {:ok, _first} = StrictIdempotentPayments.process_payment(pid, @valid, "exact")

    # The entry expires at 0 + 10_000. Sweeping at exactly 10_000 must drop it:
    # an entry is expired once its expiry timestamp has been reached.
    Clock.set(10_000)
    send(pid, :cleanup)
    # Mailbox ordering: this call is served only after the sweep completes.
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1

    # Probe from a moment at which a *surviving* entry would still be live
    # (9_999 < 10_000). Because the sweep dropped it, the key is unseen: a
    # differing-params request is processed fresh instead of conflicting.
    Clock.set(9_999)

    assert {:ok, replacement} =
             StrictIdempotentPayments.process_payment(
               pid,
               %{amount: 1, currency: "EUR", recipient: "other"},
               "exact"
             )

    assert replacement.amount == 1
    assert length(StrictIdempotentPayments.get_payments(pid)) == 2
  end

  test "a finite cleanup_interval_ms sweeps periodically without disrupting service" do
    {:ok, pid} =
      StrictIdempotentPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: 10
      )

    {:ok, first} = StrictIdempotentPayments.process_payment(pid, @valid, "live")

    # Several sweeps fire in this window; unexpired entries must survive them.
    Process.sleep(60)
    assert Process.alive?(pid)

    {:ok, cached} = StrictIdempotentPayments.process_payment(pid, @valid, "live")
    assert cached == first
    assert length(StrictIdempotentPayments.get_payments(pid)) == 1
  end
end
