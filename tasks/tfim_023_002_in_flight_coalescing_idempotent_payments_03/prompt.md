# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule CoalescingPayments do
  @moduledoc """
  A GenServer that simulates an idempotent payment system with in-flight request
  coalescing: concurrent callers sharing an idempotency key trigger the processor
  exactly once and all receive the same result. Completed keys are cached with a
  TTL; payment records are never removed.
  """

  use GenServer

  @default_ttl_ms 86_400_000
  @default_cleanup_interval_ms 60_000

  @typedoc "A payment response record."
  @type response :: %{
          id: String.t(),
          amount: integer(),
          currency: String.t(),
          recipient: String.t(),
          status: String.t(),
          created_at: integer()
        }

  @typedoc "The result returned to a caller of `process_payment/3`."
  @type result :: {:ok, response()} | {:error, term()}

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the payment server.

  Accepts `:clock`, `:ttl_ms`, `:cleanup_interval_ms`, `:processor` and the
  usual `:name` option forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Processes a payment, coalescing concurrent in-flight requests that share the
  same `idempotency_key`.

  Returns `{:ok, response}` or `{:error, reason}`. When `idempotency_key` is
  `nil` every call runs the processor independently.
  """
  @spec process_payment(GenServer.server(), map(), String.t() | nil) :: result()
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key}, 30_000)
  end

  @doc "Returns all payment records, oldest first."
  @spec get_payments(GenServer.server()) :: [response()]
  def get_payments(server), do: GenServer.call(server, :get_payments)

  @doc "Returns `{:ok, payment}` for `id` or `{:error, :not_found}`."
  @spec get_payment(GenServer.server(), String.t()) ::
          {:ok, response()} | {:error, :not_found}
  def get_payment(server, id), do: GenServer.call(server, {:get_payment, id})

  @doc "Returns the number of payments currently being processed."
  @spec in_flight_count(GenServer.server()) :: non_neg_integer()
  def in_flight_count(server), do: GenServer.call(server, :in_flight_count)

  # --------------------------------------------------------------------------
  # Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      ttl_ms: Keyword.get(opts, :ttl_ms, @default_ttl_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      processor: Keyword.get(opts, :processor, fn _params -> :ok end),
      counter: 0,
      payments: [],
      # key => {:completed, result, expiry} | {:pending, [from]}
      idempotency_keys: %{},
      # ref => from  (in-flight requests without an idempotency key)
      nil_pending: %{}
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:process_payment, params, nil}, from, state) do
    if valid_params?(params) do
      ref = make_ref()
      start_work(state.processor, params, {:nil_req, ref})
      {:noreply, %{state | nil_pending: Map.put(state.nil_pending, ref, from)}}
    else
      {:reply, {:error, :invalid_params}, state}
    end
  end

  def handle_call({:process_payment, params, key}, from, state) do
    now = state.clock.()

    case Map.get(state.idempotency_keys, key) do
      {:completed, result, expiry} when expiry > now ->
        {:reply, result, state}

      {:pending, froms} ->
        keys = Map.put(state.idempotency_keys, key, {:pending, [from | froms]})
        {:noreply, %{state | idempotency_keys: keys}}

      _ ->
        if valid_params?(params) do
          start_work(state.processor, params, {:key, key})
          keys = Map.put(state.idempotency_keys, key, {:pending, [from]})
          {:noreply, %{state | idempotency_keys: keys}}
        else
          result = {:error, :invalid_params}
          expiry = now + state.ttl_ms
          keys = Map.put(state.idempotency_keys, key, {:completed, result, expiry})
          {:reply, result, %{state | idempotency_keys: keys}}
        end
    end
  end

  def handle_call(:get_payments, _from, state) do
    {:reply, Enum.reverse(state.payments), state}
  end

  def handle_call({:get_payment, id}, _from, state) do
    case Enum.find(state.payments, &(&1.id == id)) do
      nil -> {:reply, {:error, :not_found}, state}
      payment -> {:reply, {:ok, payment}, state}
    end
  end

  def handle_call(:in_flight_count, _from, state) do
    key_pending =
      Enum.count(state.idempotency_keys, fn {_k, v} -> match?({:pending, _}, v) end)

    {:reply, key_pending + map_size(state.nil_pending), state}
  end

  @impl true
  def handle_info({:work_done, {:nil_req, ref}, params, outcome}, state) do
    {from, nil_pending} = Map.pop(state.nil_pending, ref)
    {result, state} = finalize(state, params, outcome)
    if from, do: GenServer.reply(from, result)
    {:noreply, %{state | nil_pending: nil_pending}}
  end

  def handle_info({:work_done, {:key, key}, params, outcome}, state) do
    {result, state} = finalize(state, params, outcome)
    expiry = state.clock.() + state.ttl_ms
    {entry, keys} = Map.pop(state.idempotency_keys, key)

    froms =
      case entry do
        {:pending, fs} -> fs
        _ -> []
      end

    keys = Map.put(keys, key, {:completed, result, expiry})
    Enum.each(froms, fn from -> GenServer.reply(from, result) end)
    {:noreply, %{state | idempotency_keys: keys}}
  end

  def handle_info(:cleanup, state) do
    now = state.clock.()

    kept =
      state.idempotency_keys
      |> Enum.filter(fn
        {_k, {:completed, _r, expiry}} -> expiry > now
        {_k, {:pending, _}} -> true
      end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | idempotency_keys: kept}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --------------------------------------------------------------------------
  # Internals
  # --------------------------------------------------------------------------

  defp start_work(processor, params, tag) do
    server = self()

    spawn(fn ->
      outcome =
        try do
          processor.(params)
        rescue
          e -> {:error, {:exception, Exception.message(e)}}
        end

      send(server, {:work_done, tag, params, outcome})
    end)
  end

  defp finalize(state, params, :ok) do
    counter = state.counter + 1
    id = "pay_#{counter}"

    response = %{
      id: id,
      amount: params.amount,
      currency: params.currency,
      recipient: params.recipient,
      status: "completed",
      created_at: state.clock.()
    }

    state = %{state | counter: counter, payments: [response | state.payments]}
    {{:ok, response}, state}
  end

  defp finalize(state, _params, {:error, reason}) do
    {{:error, reason}, state}
  end

  defp valid_params?(params) do
    is_map(params) and
      Map.has_key?(params, :amount) and
      Map.has_key?(params, :currency) and
      Map.has_key?(params, :recipient)
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) when is_integer(interval) do
    Process.send_after(self(), :cleanup, interval)
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
