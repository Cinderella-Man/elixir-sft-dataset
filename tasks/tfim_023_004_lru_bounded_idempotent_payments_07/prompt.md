# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule BoundedIdempotentPayments do
  @moduledoc """
  A GenServer that simulates an idempotent payment system whose idempotency store
  is capacity-bounded with least-recently-used eviction instead of TTL expiry.
  Recency is tracked with an internal monotonic tick. Payment records themselves
  are never evicted.
  """

  use GenServer

  @default_max_keys 1000

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the server. Accepts `:max_keys` (a positive integer, default 1000) and
  `:clock` (a zero-arity ms clock). Raises `ArgumentError` when `:max_keys` is
  not a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    max_keys = Keyword.get(opts, :max_keys, @default_max_keys)

    unless is_integer(max_keys) and max_keys > 0 do
      raise ArgumentError, ":max_keys must be a positive integer"
    end

    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Processes a payment. With `nil` key a new record is always created; with a key,
  a cached result is returned (and its recency refreshed) or the payment is
  processed and stored under LRU bounds.
  """
  @spec process_payment(GenServer.server(), map(), String.t() | nil) ::
          {:ok, map()} | {:error, :invalid_params}
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end

  @doc "Returns all payment records, oldest first."
  @spec get_payments(GenServer.server()) :: [map()]
  def get_payments(server), do: GenServer.call(server, :get_payments)

  @doc "Fetches a payment record by id."
  @spec get_payment(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_payment(server, id), do: GenServer.call(server, {:get_payment, id})

  @doc "Returns retained idempotency keys ordered least-recently-used first."
  @spec keys_by_recency(GenServer.server()) :: [String.t()]
  def keys_by_recency(server), do: GenServer.call(server, :keys_by_recency)

  # --------------------------------------------------------------------------
  # Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(opts) do
    max_keys = Keyword.get(opts, :max_keys, @default_max_keys)

    state = %{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      max_keys: max_keys,
      tick: 0,
      counter: 0,
      payments: [],
      # key => {result, last_used_tick}
      idempotency_keys: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:process_payment, params, nil}, _from, state) do
    {result, state} = do_process(state, params)
    {:reply, result, state}
  end

  def handle_call({:process_payment, params, key}, _from, state) do
    case Map.get(state.idempotency_keys, key) do
      {result, _tick} ->
        # Cache hit: return cached result and refresh recency.
        {tick, state} = next_tick(state)
        keys = Map.put(state.idempotency_keys, key, {result, tick})
        {:reply, result, %{state | idempotency_keys: keys}}

      nil ->
        {result, state} = do_process(state, params)
        state = insert_key(state, key, result)
        {:reply, result, state}
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

  def handle_call(:keys_by_recency, _from, state) do
    keys =
      state.idempotency_keys
      |> Enum.sort_by(fn {_key, {_result, tick}} -> tick end)
      |> Enum.map(fn {key, _} -> key end)

    {:reply, keys, state}
  end

  # --------------------------------------------------------------------------
  # Internals
  # --------------------------------------------------------------------------

  defp do_process(state, params) do
    if valid_params?(params) do
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

      {{:ok, response}, %{state | counter: counter, payments: [response | state.payments]}}
    else
      {{:error, :invalid_params}, state}
    end
  end

  defp insert_key(state, key, result) do
    state =
      if map_size(state.idempotency_keys) >= state.max_keys do
        evict_lru(state)
      else
        state
      end

    {tick, state} = next_tick(state)
    %{state | idempotency_keys: Map.put(state.idempotency_keys, key, {result, tick})}
  end

  defp evict_lru(state) do
    {lru_key, _} =
      Enum.min_by(state.idempotency_keys, fn {_key, {_result, tick}} -> tick end)

    %{state | idempotency_keys: Map.delete(state.idempotency_keys, lru_key)}
  end

  defp next_tick(state) do
    tick = state.tick + 1
    {tick, %{state | tick: tick}}
  end

  defp valid_params?(params) do
    is_map(params) and
      Map.has_key?(params, :amount) and
      Map.has_key?(params, :currency) and
      Map.has_key?(params, :recipient)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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

  test "omitted :max_keys retains exactly 1000 keys before evicting the LRU", %{pid: _pid} do
    {:ok, srv} = BoundedIdempotentPayments.start_link(clock: &Clock.now/0)

    for i <- 1..1000 do
      {:ok, _} = BoundedIdempotentPayments.process_payment(srv, @valid, "k-#{i}")
    end

    # nothing evicted yet at exactly the default budget
    keys = BoundedIdempotentPayments.keys_by_recency(srv)
    assert length(keys) == 1000
    assert List.first(keys) == "k-1"
    assert List.last(keys) == "k-1000"

    # the 1001st brand-new key overflows the default budget -> LRU "k-1" goes
    {:ok, _} = BoundedIdempotentPayments.process_payment(srv, @valid, "k-1001")
    keys = BoundedIdempotentPayments.keys_by_recency(srv)
    assert length(keys) == 1000
    assert List.first(keys) == "k-2"
    assert List.last(keys) == "k-1001"

    # "k-1" was evicted -> reprocessed into a fresh record (and evicts "k-2")
    before = length(BoundedIdempotentPayments.get_payments(srv))
    {:ok, _} = BoundedIdempotentPayments.process_payment(srv, @valid, "k-1")
    assert length(BoundedIdempotentPayments.get_payments(srv)) == before + 1

    # a still-retained key is a cache hit -> no new record
    {:ok, _} = BoundedIdempotentPayments.process_payment(srv, @valid, "k-3")
    assert length(BoundedIdempotentPayments.get_payments(srv)) == before + 1
  end

  test "starts with no options and stamps :created_at from the default clock", %{pid: _pid} do
    {:ok, srv} = BoundedIdempotentPayments.start_link([])

    assert {:ok, resp} = BoundedIdempotentPayments.process_payment(srv, @valid, "d")
    assert is_integer(resp.created_at)
    assert resp.status == "completed"
    assert BoundedIdempotentPayments.keys_by_recency(srv) == ["d"]
  end
end
```
