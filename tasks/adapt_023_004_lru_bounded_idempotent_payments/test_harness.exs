defmodule BoundedIdempotentPaymentsTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    def start_link(initial \\ 0), do: Agent.start_link(fn -> initial end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
  end

  @valid %{amount: 5000, currency: "USD", recipient: "merchant_42"}

  setup do
    start_supervised!({Clock, 0})
    {:ok, pid} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 1000)
    %{pid: pid}
  end

  test "raises for invalid :max_keys" do
    assert_raise ArgumentError, fn ->
      BoundedIdempotentPayments.start_link(max_keys: 0)
    end

    assert_raise ArgumentError, fn ->
      BoundedIdempotentPayments.start_link(max_keys: :lots)
    end
  end

  test "processes a payment and returns a response", %{pid: pid} do
    assert {:ok, resp} = BoundedIdempotentPayments.process_payment(pid, @valid)
    assert resp.amount == 5000
    assert resp.status == "completed"
    assert is_binary(resp.id)
    assert is_integer(resp.created_at)
  end

  test "requests without idempotency key always create new records", %{pid: pid} do
    {:ok, r1} = BoundedIdempotentPayments.process_payment(pid, @valid)
    {:ok, r2} = BoundedIdempotentPayments.process_payment(pid, @valid)
    assert r1.id != r2.id
    assert length(BoundedIdempotentPayments.get_payments(pid)) == 2
  end

  test "same key returns cached result without a duplicate record", %{pid: pid} do
    {:ok, first} = BoundedIdempotentPayments.process_payment(pid, @valid, "k")
    {:ok, second} = BoundedIdempotentPayments.process_payment(pid, @valid, "k")
    assert first == second
    assert length(BoundedIdempotentPayments.get_payments(pid)) == 1
  end

  test "eviction: a new key at capacity drops the least-recently-used key", %{pid: _pid} do
    {:ok, pid} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 2)

    {:ok, _a} = BoundedIdempotentPayments.process_payment(pid, @valid, "a")
    {:ok, _b} = BoundedIdempotentPayments.process_payment(pid, @valid, "b")
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["a", "b"]

    # "c" overflows -> evicts LRU ("a")
    {:ok, _c} = BoundedIdempotentPayments.process_payment(pid, @valid, "c")
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["b", "c"]

    # "a" was evicted -> reprocessed as a brand new record
    before = length(BoundedIdempotentPayments.get_payments(pid))
    {:ok, _a2} = BoundedIdempotentPayments.process_payment(pid, @valid, "a")
    assert length(BoundedIdempotentPayments.get_payments(pid)) == before + 1
  end

  test "textbook LRU trace with touch-protection", %{pid: _pid} do
    {:ok, pid} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 2)

    {:ok, a1} = BoundedIdempotentPayments.process_payment(pid, @valid, "a")
    {:ok, _b1} = BoundedIdempotentPayments.process_payment(pid, @valid, "b")

    # touch "a" -> "b" becomes LRU
    {:ok, a_hit} = BoundedIdempotentPayments.process_payment(pid, @valid, "a")
    assert a_hit == a1
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["b", "a"]

    # "c" overflows -> evicts "b" (not the touched "a")
    {:ok, _c1} = BoundedIdempotentPayments.process_payment(pid, @valid, "c")
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["a", "c"]

    # "a" still cached (same id), "b" was evicted -> fresh record
    {:ok, a_again} = BoundedIdempotentPayments.process_payment(pid, @valid, "a")
    assert a_again == a1

    {:ok, b2} = BoundedIdempotentPayments.process_payment(pid, @valid, "b")
    assert b2.id != a1.id

    # a -> pay_1, b -> pay_2, c -> pay_3, b(again) -> pay_4
    assert length(BoundedIdempotentPayments.get_payments(pid)) == 4
  end

  test "cache hit does not create a record and refreshes recency", %{pid: _pid} do
    {:ok, pid} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 3)

    {:ok, _} = BoundedIdempotentPayments.process_payment(pid, @valid, "x")
    {:ok, _} = BoundedIdempotentPayments.process_payment(pid, @valid, "y")
    {:ok, _} = BoundedIdempotentPayments.process_payment(pid, @valid, "z")
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["x", "y", "z"]

    # touch "x": becomes MRU, y now LRU
    {:ok, _} = BoundedIdempotentPayments.process_payment(pid, @valid, "x")
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["y", "z", "x"]
    assert length(BoundedIdempotentPayments.get_payments(pid)) == 3
  end

  test "returns error for missing required fields", %{pid: pid} do
    assert {:error, :invalid_params} =
             BoundedIdempotentPayments.process_payment(pid, %{amount: 100})
  end

  test "error results are cached under the key and occupy a slot", %{pid: _pid} do
    {:ok, pid} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 2)

    r1 = BoundedIdempotentPayments.process_payment(pid, %{amount: 100}, "bad")
    r2 = BoundedIdempotentPayments.process_payment(pid, %{amount: 100}, "bad")
    assert r1 == {:error, :invalid_params}
    assert r2 == {:error, :invalid_params}
    assert BoundedIdempotentPayments.get_payments(pid) == []

    # "bad" occupies a slot in the LRU store
    assert BoundedIdempotentPayments.keys_by_recency(pid) == ["bad"]
  end

  test "get_payment retrieves by id and reports not found", %{pid: pid} do
    {:ok, resp} = BoundedIdempotentPayments.process_payment(pid, @valid)
    assert {:ok, found} = BoundedIdempotentPayments.get_payment(pid, resp.id)
    assert found.id == resp.id
    assert {:error, :not_found} = BoundedIdempotentPayments.get_payment(pid, "pay_nope")
  end

  test "payment records are never evicted even as keys churn", %{pid: _pid} do
    {:ok, pid} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 3)

    for i <- 1..20 do
      BoundedIdempotentPayments.process_payment(pid, @valid, "key-#{i}")
    end

    # Only 3 keys retained, but all 20 payment records survive
    assert length(BoundedIdempotentPayments.keys_by_recency(pid)) == 3
    assert length(BoundedIdempotentPayments.get_payments(pid)) == 20
  end

  test "payment IDs are unique and sequential", %{pid: pid} do
    {:ok, r1} = BoundedIdempotentPayments.process_payment(pid, @valid)
    {:ok, r2} = BoundedIdempotentPayments.process_payment(pid, @valid)
    {:ok, r3} = BoundedIdempotentPayments.process_payment(pid, @valid)
    ids = [r1.id, r2.id, r3.id]
    assert ids == Enum.uniq(ids)
  end

  test "get_payments lists records oldest first", %{pid: pid} do
    {:ok, r1} = BoundedIdempotentPayments.process_payment(pid, %{@valid | amount: 1})
    {:ok, r2} = BoundedIdempotentPayments.process_payment(pid, %{@valid | amount: 2})
    {:ok, r3} = BoundedIdempotentPayments.process_payment(pid, %{@valid | amount: 3})

    records = BoundedIdempotentPayments.get_payments(pid)
    assert Enum.map(records, & &1.id) == [r1.id, r2.id, r3.id]
    assert Enum.map(records, & &1.amount) == [1, 2, 3]
  end

  test "response ids follow the counter-based pay_N form in order", %{pid: pid} do
    {:ok, r1} = BoundedIdempotentPayments.process_payment(pid, @valid)
    {:ok, r2} = BoundedIdempotentPayments.process_payment(pid, @valid, "key-a")
    {:ok, r3} = BoundedIdempotentPayments.process_payment(pid, @valid)

    assert r1.id == "pay_1"
    assert r2.id == "pay_2"
    assert r3.id == "pay_3"
    assert r2.currency == "USD"
    assert r2.recipient == "merchant_42"
    assert r2.status == "completed"
    assert r2.created_at == Clock.now()
  end

  test "cached error key refreshes recency on hit and survives eviction", %{pid: _pid} do
    {:ok, srv} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0, max_keys: 2)

    assert {:error, :invalid_params} =
             BoundedIdempotentPayments.process_payment(srv, %{amount: 100}, "bad")

    {:ok, _} = BoundedIdempotentPayments.process_payment(srv, @valid, "good")
    assert BoundedIdempotentPayments.keys_by_recency(srv) == ["bad", "good"]

    # a hit on the error key refreshes its recency, making "good" the LRU
    assert {:error, :invalid_params} =
             BoundedIdempotentPayments.process_payment(srv, %{amount: 100}, "bad")

    assert BoundedIdempotentPayments.keys_by_recency(srv) == ["good", "bad"]

    # overflow evicts "good", not the touched error key
    {:ok, _} = BoundedIdempotentPayments.process_payment(srv, @valid, "third")
    assert BoundedIdempotentPayments.keys_by_recency(srv) == ["bad", "third"]
    assert length(BoundedIdempotentPayments.get_payments(srv)) == 2
  end

  test "clock only stamps :created_at and never drives recency order", %{pid: _pid} do
    {:ok, agent} = Agent.start_link(fn -> 500 end)
    clock = fn -> Agent.get_and_update(agent, fn n -> {n, n - 100} end) end
    {:ok, srv} = BoundedIdempotentPayments.start_link(clock: clock, max_keys: 2)

    {:ok, a} = BoundedIdempotentPayments.process_payment(srv, @valid, "a")
    {:ok, b} = BoundedIdempotentPayments.process_payment(srv, @valid, "b")
    assert a.created_at == 500
    assert b.created_at == 400

    # despite a descending clock, recency follows the internal tick
    assert BoundedIdempotentPayments.keys_by_recency(srv) == ["a", "b"]

    {:ok, c} = BoundedIdempotentPayments.process_payment(srv, @valid, "c")
    assert c.created_at == 300
    assert BoundedIdempotentPayments.keys_by_recency(srv) == ["b", "c"]
  end
end
