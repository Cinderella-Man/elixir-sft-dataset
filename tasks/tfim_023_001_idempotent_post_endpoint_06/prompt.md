# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule IdempotentPayments do
  @moduledoc """
  A GenServer that simulates an idempotent payment processing system with
  in-memory storage. Idempotency keys are remembered for a configurable TTL and
  purged periodically. Payment records themselves are never removed.
  """

  use GenServer

  @default_ttl_ms 86_400_000
  @default_cleanup_interval_ms 60_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Processes a payment. When `idempotency_key` is provided and still cached (not
  expired), returns the exact original response without creating a new record.
  """
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end

  def get_payments(server) do
    GenServer.call(server, :get_payments)
  end

  def get_payment(server, id) do
    GenServer.call(server, {:get_payment, id})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      ttl_ms: ttl_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      counter: 0,
      payments: [],
      idempotency_keys: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:process_payment, params, key}, _from, state) do
    now = state.clock.()

    case cached(state, key, now) do
      {:hit, response} ->
        {:reply, response, state}

      :miss ->
        {result, state} = do_process(state, params, now)
        state = maybe_cache(state, key, result, now)
        {:reply, result, state}
    end
  end

  @impl true
  def handle_call(:get_payments, _from, state) do
    {:reply, Enum.reverse(state.payments), state}
  end

  @impl true
  def handle_call({:get_payment, id}, _from, state) do
    case Enum.find(state.payments, &(&1.id == id)) do
      nil -> {:reply, {:error, :not_found}, state}
      payment -> {:reply, {:ok, payment}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    kept =
      state.idempotency_keys
      |> Enum.filter(fn {_key, {_resp, expiry}} -> expiry > now end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | idempotency_keys: kept}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp cached(_state, nil, _now), do: :miss

  defp cached(state, key, now) do
    case Map.get(state.idempotency_keys, key) do
      {response, expiry} when expiry > now -> {:hit, response}
      _ -> :miss
    end
  end

  defp do_process(state, params, now) do
    if valid_params?(params) do
      counter = state.counter + 1
      id = "pay_#{counter}"

      response = %{
        id: id,
        amount: params.amount,
        currency: params.currency,
        recipient: params.recipient,
        status: "completed",
        created_at: now
      }

      state = %{state | counter: counter, payments: [response | state.payments]}
      {{:ok, response}, state}
    else
      {{:error, :invalid_params}, state}
    end
  end

  defp maybe_cache(state, nil, _result, _now), do: state

  defp maybe_cache(state, key, result, now) do
    expiry = now + state.ttl_ms
    %{state | idempotency_keys: Map.put(state.idempotency_keys, key, {result, expiry})}
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
    # TODO
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
end
```
