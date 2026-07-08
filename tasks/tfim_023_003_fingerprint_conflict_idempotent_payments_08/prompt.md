# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule StrictIdempotentPayments do
  @moduledoc """
  A GenServer that simulates an idempotent payment system with request-fingerprint
  conflict detection: replaying an idempotency key with a different request body
  returns `{:error, :idempotency_key_conflict}` instead of the cached response.
  Entries expire on a TTL; payment records are never removed.
  """

  use GenServer

  @default_ttl_ms 86_400_000
  @default_cleanup_interval_ms 60_000

  @typedoc "Parameters describing a payment request."
  @type params :: map()

  @typedoc "A stored payment record / successful response."
  @type payment :: %{
          id: String.t(),
          amount: integer(),
          currency: String.t(),
          recipient: String.t(),
          status: String.t(),
          created_at: integer()
        }

  @typedoc "The result of processing a payment."
  @type process_result ::
          {:ok, payment()}
          | {:error, :invalid_params}
          | {:error, :idempotency_key_conflict}

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the payment server.

  Options: `:clock` (zero-arity ms clock), `:ttl_ms`, `:cleanup_interval_ms`
  (`:infinity` disables the periodic purge), and `:name`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Processes a payment.

  With a `nil` idempotency key a new record is always created. With a key, a
  matching-fingerprint replay returns the cached result, a differing-fingerprint
  replay returns `{:error, :idempotency_key_conflict}`, and an expired/unseen key
  is processed fresh.
  """
  @spec process_payment(GenServer.server(), params(), String.t() | nil) :: process_result()
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end

  @doc "Returns all payment records, oldest first."
  @spec get_payments(GenServer.server()) :: [payment()]
  def get_payments(server), do: GenServer.call(server, :get_payments)

  @doc "Fetches a payment by id, returning `{:ok, payment}` or `{:error, :not_found}`."
  @spec get_payment(GenServer.server(), String.t()) :: {:ok, payment()} | {:error, :not_found}
  def get_payment(server, id), do: GenServer.call(server, {:get_payment, id})

  # --------------------------------------------------------------------------
  # Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      ttl_ms: Keyword.get(opts, :ttl_ms, @default_ttl_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      counter: 0,
      payments: [],
      # key => {result, fingerprint, expiry}
      idempotency_keys: %{}
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:process_payment, params, nil}, _from, state) do
    {result, state} = do_process(state, params)
    {:reply, result, state}
  end

  def handle_call({:process_payment, params, key}, _from, state) do
    now = state.clock.()
    fp = fingerprint(params)

    case Map.get(state.idempotency_keys, key) do
      {result, stored_fp, expiry} when expiry > now ->
        if stored_fp == fp do
          {:reply, result, state}
        else
          {:reply, {:error, :idempotency_key_conflict}, state}
        end

      _ ->
        {result, state} = do_process(state, params)
        expiry = now + state.ttl_ms
        keys = Map.put(state.idempotency_keys, key, {result, fp, expiry})
        {:reply, result, %{state | idempotency_keys: keys}}
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

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    kept =
      state.idempotency_keys
      |> Enum.filter(fn {_key, {_result, _fp, expiry}} -> expiry > now end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | idempotency_keys: kept}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

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

  defp fingerprint(params), do: :erlang.phash2(params)

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
    # TODO
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
```
