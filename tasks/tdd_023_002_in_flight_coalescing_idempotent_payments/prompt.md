# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule CoalescingPaymentsTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    def start_link(initial \\ 0), do: Agent.start_link(fn -> initial end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  defmodule Calls do
    use Agent
    def start_link(_ \\ nil), do: Agent.start_link(fn -> 0 end, name: __MODULE__)
    def bump, do: Agent.update(__MODULE__, &(&1 + 1))
    def count, do: Agent.get(__MODULE__, & &1)
  end

  @valid %{amount: 5000, currency: "USD", recipient: "merchant_42"}

  setup do
    start_supervised!({Clock, 0})
    start_supervised!({Calls, nil})

    processor = fn _params ->
      Calls.bump()
      Process.sleep(150)
      :ok
    end

    {:ok, pid} =
      CoalescingPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity,
        processor: processor
      )

    %{pid: pid}
  end

  test "processes a payment and returns a response", %{pid: pid} do
    assert {:ok, resp} = CoalescingPayments.process_payment(pid, @valid)
    assert resp.amount == 5000
    assert resp.currency == "USD"
    assert resp.recipient == "merchant_42"
    assert resp.status == "completed"
    assert is_binary(resp.id)
    assert is_integer(resp.created_at)
    assert Calls.count() == 1
  end

  test "concurrent requests with same key coalesce into one processing", %{pid: pid} do
    tasks =
      for _ <- 1..10 do
        Task.async(fn -> CoalescingPayments.process_payment(pid, @valid, "same-key") end)
      end

    results = Task.await_many(tasks, 5000)

    # All ten callers received the identical shared result
    assert Enum.uniq(results) |> length() == 1
    assert [{:ok, _}] = Enum.uniq(results)

    # Processor ran exactly once, and exactly one payment record was created
    assert Calls.count() == 1
    assert length(CoalescingPayments.get_payments(pid)) == 1
  end

  test "in_flight_count reflects pending work", %{pid: pid} do
    parent = self()

    spawn(fn ->
      send(parent, {:done, CoalescingPayments.process_payment(pid, @valid, "slow")})
    end)

    Process.sleep(50)
    assert CoalescingPayments.in_flight_count(pid) == 1

    assert_receive {:done, {:ok, _}}, 2000
    assert CoalescingPayments.in_flight_count(pid) == 0
  end

  test "completed key returns cached result without re-running processor", %{pid: pid} do
    {:ok, first} = CoalescingPayments.process_payment(pid, @valid, "k")
    {:ok, second} = CoalescingPayments.process_payment(pid, @valid, "k")

    assert first == second
    assert Calls.count() == 1
    assert length(CoalescingPayments.get_payments(pid)) == 1
  end

  test "requests without idempotency key always create new records", %{pid: pid} do
    tasks =
      for _ <- 1..5 do
        Task.async(fn -> CoalescingPayments.process_payment(pid, @valid) end)
      end

    results = Task.await_many(tasks, 5000)
    ids = Enum.map(results, fn {:ok, r} -> r.id end)

    assert length(Enum.uniq(ids)) == 5
    assert Calls.count() == 5
    assert length(CoalescingPayments.get_payments(pid)) == 5
  end

  test "different idempotency keys create separate records", %{pid: pid} do
    {:ok, r1} = CoalescingPayments.process_payment(pid, @valid, "key-1")
    {:ok, r2} = CoalescingPayments.process_payment(pid, @valid, "key-2")

    assert r1.id != r2.id
    assert length(CoalescingPayments.get_payments(pid)) == 2
  end

  test "expired idempotency key allows reprocessing", %{pid: pid} do
    {:ok, first} = CoalescingPayments.process_payment(pid, @valid, "ttl")
    Clock.advance(10_001)
    {:ok, second} = CoalescingPayments.process_payment(pid, @valid, "ttl")

    assert first.id != second.id
    assert length(CoalescingPayments.get_payments(pid)) == 2
  end

  test "returns error for missing required fields without calling processor", %{pid: pid} do
    assert {:error, :invalid_params} = CoalescingPayments.process_payment(pid, %{amount: 100})
    assert Calls.count() == 0
  end

  test "processor errors are cached under the idempotency key", %{} do
    {:ok, decline_pid} =
      CoalescingPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity,
        processor: fn _ -> {:error, :gateway_declined} end
      )

    r1 = CoalescingPayments.process_payment(decline_pid, @valid, "bad")
    r2 = CoalescingPayments.process_payment(decline_pid, @valid, "bad")

    assert r1 == {:error, :gateway_declined}
    assert r2 == {:error, :gateway_declined}
    assert CoalescingPayments.get_payments(decline_pid) == []
  end

  test "get_payment retrieves and reports not found", %{pid: pid} do
    {:ok, resp} = CoalescingPayments.process_payment(pid, @valid)
    assert {:ok, found} = CoalescingPayments.get_payment(pid, resp.id)
    assert found.id == resp.id
    assert {:error, :not_found} = CoalescingPayments.get_payment(pid, "pay_nope")
  end

  test "cleanup removes expired idempotency entries but keeps payment records", %{pid: pid} do
    for i <- 1..20 do
      CoalescingPayments.process_payment(pid, @valid, "batch-#{i}")
    end

    assert length(CoalescingPayments.get_payments(pid)) == 20

    Clock.advance(10_001)
    send(pid, :cleanup)

    # A synchronous call cannot be answered until the cleanup message ahead of it
    # has been handled, and it shows that no work is left in flight.
    assert CoalescingPayments.in_flight_count(pid) == 0

    assert length(CoalescingPayments.get_payments(pid)) == 20

    # The expired key no longer short-circuits: the payment is processed again.
    {:ok, _} = CoalescingPayments.process_payment(pid, @valid, "batch-1")
    assert length(CoalescingPayments.get_payments(pid)) == 21
  end

  test "payment IDs are unique and sequential", %{pid: pid} do
    {:ok, r1} = CoalescingPayments.process_payment(pid, @valid)
    {:ok, r2} = CoalescingPayments.process_payment(pid, @valid)
    {:ok, r3} = CoalescingPayments.process_payment(pid, @valid)
    ids = [r1.id, r2.id, r3.id]
    assert ids == Enum.uniq(ids)
  end

  test "raising processor produces a cached exception error and the server survives" do
    {:ok, pid} =
      CoalescingPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity,
        processor: fn _params -> raise ArgumentError, "gateway exploded" end
      )

    assert {:error, {:exception, "gateway exploded"}} =
             CoalescingPayments.process_payment(pid, @valid, "boom")

    # Cached like any other result: the processor is not re-run for the same key.
    assert {:error, {:exception, "gateway exploded"}} =
             CoalescingPayments.process_payment(pid, @valid, "boom")

    assert Process.alive?(pid)
    assert CoalescingPayments.get_payments(pid) == []
    assert CoalescingPayments.in_flight_count(pid) == 0
  end

  test "caller joining a pending key gets the group result even with invalid params" do
    test_pid = self()

    processor = fn _params ->
      send(test_pid, {:worker, self()})

      receive do
        :release -> :ok
      end
    end

    {:ok, pid} =
      CoalescingPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity,
        processor: processor
      )

    first = Task.async(fn -> CoalescingPayments.process_payment(pid, @valid, "group") end)
    assert_receive {:worker, worker}, 2000

    spawn(fn ->
      send(test_pid, {:second, CoalescingPayments.process_payment(pid, %{junk: true}, "group")})
    end)

    # The joiner must block on the pending group, not be rejected as invalid_params.
    refute_receive {:second, _}, 200
    assert CoalescingPayments.in_flight_count(pid) == 1

    send(worker, :release)

    assert_receive {:second, {:ok, second}}, 2000
    assert {:ok, first_result} = Task.await(first, 2000)
    assert second == first_result
    assert second.recipient == "merchant_42"
    assert length(CoalescingPayments.get_payments(pid)) == 1
  end

  test "invalid params cached under a key shadow later valid params until expiry", %{pid: pid} do
    assert {:error, :invalid_params} =
             CoalescingPayments.process_payment(pid, %{amount: 100}, "poisoned")

    assert CoalescingPayments.in_flight_count(pid) == 0

    assert {:error, :invalid_params} =
             CoalescingPayments.process_payment(pid, @valid, "poisoned")

    assert Calls.count() == 0
    assert CoalescingPayments.get_payments(pid) == []

    Clock.advance(10_001)
    assert {:ok, _} = CoalescingPayments.process_payment(pid, @valid, "poisoned")
    assert Calls.count() == 1
  end

  test "key whose expiry exactly equals the clock is reprocessed", %{pid: pid} do
    {:ok, first} = CoalescingPayments.process_payment(pid, @valid, "edge")

    Clock.advance(10_000)

    {:ok, second} = CoalescingPayments.process_payment(pid, @valid, "edge")

    assert first.id != second.id
    assert Calls.count() == 2
    assert length(CoalescingPayments.get_payments(pid)) == 2
  end

  test "cleanup far past the TTL keeps an in-flight key and still replies to its waiter" do
    test_pid = self()

    processor = fn _params ->
      send(test_pid, {:worker, self()})

      receive do
        :release -> :ok
      end
    end

    {:ok, pid} =
      CoalescingPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity,
        processor: processor
      )

    spawn(fn ->
      send(test_pid, {:res, CoalescingPayments.process_payment(pid, @valid, "long")})
    end)

    assert_receive {:worker, worker}, 2000

    Clock.advance(10_000_000)
    send(pid, :cleanup)

    # The synchronous call proves the cleanup ahead of it was handled.
    assert CoalescingPayments.in_flight_count(pid) == 1

    send(worker, :release)

    assert_receive {:res, {:ok, resp}}, 2000
    assert resp.status == "completed"
    assert CoalescingPayments.in_flight_count(pid) == 0
    assert length(CoalescingPayments.get_payments(pid)) == 1
  end

  test "declines and invalid params consume no counter so the first success is pay_1" do
    processor = fn _params ->
      Calls.bump()
      if Calls.count() == 1, do: {:error, :gateway_declined}, else: :ok
    end

    {:ok, pid} =
      CoalescingPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: :infinity,
        processor: processor
      )

    assert {:error, :gateway_declined} = CoalescingPayments.process_payment(pid, @valid)
    assert {:error, :invalid_params} = CoalescingPayments.process_payment(pid, %{amount: 1})

    assert {:ok, r1} = CoalescingPayments.process_payment(pid, @valid)
    assert {:ok, r2} = CoalescingPayments.process_payment(pid, @valid)

    assert r1.id == "pay_1"
    assert r2.id == "pay_2"
    assert Enum.map(CoalescingPayments.get_payments(pid), & &1.id) == ["pay_1", "pay_2"]
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
