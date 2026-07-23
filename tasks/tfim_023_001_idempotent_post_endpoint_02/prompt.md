# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule IdempotentPayments do
  @moduledoc """
  A GenServer that simulates an idempotent payment processing system with
  in-memory storage.

  Payments are stored in memory and given sequential ids (`"pay_1"`, `"pay_2"`,
  ...). When an idempotency key is supplied, the response produced for that key
  is cached until `now + ttl_ms`; replaying the key inside that window returns
  the original response verbatim and creates no new payment record. A periodic
  `:cleanup` sweep purges only entries whose expiry has been reached. Payment
  records themselves are never removed.
  """

  use GenServer

  @default_ttl_ms 86_400_000
  @default_cleanup_interval_ms 60_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the payment server.

  Options:

    * `:clock` — zero-arity function returning the current time in milliseconds
      (default `fn -> System.monotonic_time(:millisecond) end`).
    * `:ttl_ms` — how long idempotency keys are remembered (default 86_400_000).
    * `:cleanup_interval_ms` — how often expired idempotency entries are purged
      (default 60_000). Pass `:infinity` to disable automatic cleanup.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Processes a payment.

  When `idempotency_key` is provided and still cached (its expiry has not been
  reached), returns the exact original response and creates no new record.
  Otherwise the payment is processed, and — when a key was given — the result is
  cached for a fresh TTL window. Missing `:amount`, `:currency` or `:recipient`
  yields `{:error, :invalid_params}`, which is cached like any other response.
  """
  @spec process_payment(GenServer.server(), map(), String.t() | nil) ::
          {:ok, map()} | {:error, :invalid_params}
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end

  @doc """
  Returns every payment record created so far, in creation order.
  """
  @spec get_payments(GenServer.server()) :: [map()]
  def get_payments(server) do
    GenServer.call(server, :get_payments)
  end

  @doc """
  Looks up a single payment record by its id.
  """
  @spec get_payment(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
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

  defp schedule_cleanup(interval) do
    if interval != :infinity do
      Process.send_after(self(), :cleanup, interval)
    end
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
    # TODO
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

  test "key is expired exactly at its expiry timestamp", %{pid: pid} do
    key = "idem-exact-boundary"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # The entry was cached at t=0 with ttl_ms 10_000, so it expires at t=10_000.
    # At that exact instant the key is no longer remembered.
    Clock.advance(10_000)

    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)

    assert second.id != first.id
    assert length(IdempotentPayments.get_payments(pid)) == 2
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

  test "cleanup purges an entry that reached its expiry timestamp exactly", %{pid: pid} do
    key = "sweep-boundary"

    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, key)

    # Entry cached at t=0 expires at t=10_000. Sweep at exactly that instant:
    # the entry has expired and must be purged.
    Clock.set(10_000)
    send(pid, :cleanup)
    # Ordered call: guarantees the sweep above has been handled already.
    assert length(IdempotentPayments.get_payments(pid)) == 1

    # The clock is injected, so move it back inside the original TTL window.
    # Had the sweep wrongly kept the entry, this replay would be a cache hit.
    Clock.set(5_000)

    {:ok, second} = IdempotentPayments.process_payment(pid, @valid_params, key)
    assert second.id != first.id
    assert length(IdempotentPayments.get_payments(pid)) == 2
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

  test "counter-based ids start at pay_1 and increment by one per record", %{pid: pid} do
    {:ok, r1} = IdempotentPayments.process_payment(pid, @valid_params)
    {:ok, r2} = IdempotentPayments.process_payment(pid, @valid_params, "seq-key")
    # Cache hit: must not consume an id.
    {:ok, r2_replay} = IdempotentPayments.process_payment(pid, @valid_params, "seq-key")
    {:ok, r3} = IdempotentPayments.process_payment(pid, @valid_params)

    assert r1.id == "pay_1"
    assert r2.id == "pay_2"
    assert r2_replay.id == "pay_2"
    assert r3.id == "pay_3"

    ids = pid |> IdempotentPayments.get_payments() |> Enum.map(& &1.id)
    assert ids == ["pay_1", "pay_2", "pay_3"]

    assert {:ok, found} = IdempotentPayments.get_payment(pid, "pay_2")
    assert found.id == "pay_2"
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

  # -------------------------------------------------------
  # Automatic cleanup scheduling
  # -------------------------------------------------------

  test "cleanup_interval_ms sweeps expired entries without an explicit message" do
    {:ok, server} =
      IdempotentPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: 20
      )

    {:ok, first} = IdempotentPayments.process_payment(server, @valid_params, "auto-key")

    # The entry expires at 10_000; leave the clock there long enough for several
    # scheduled sweeps to fire on their own.
    Clock.set(10_001)
    Process.sleep(150)

    # Rewind the injected clock: the entry, if it had survived, would still be a
    # live cache hit. A new record proves an automatic sweep purged it.
    Clock.set(0)

    {:ok, second} = IdempotentPayments.process_payment(server, @valid_params, "auto-key")
    assert second.id != first.id
    assert length(IdempotentPayments.get_payments(server)) == 2
  end

  test "cleanup_interval_ms :infinity disables automatic sweeps", %{pid: pid} do
    {:ok, first} = IdempotentPayments.process_payment(pid, @valid_params, "infinity-key")

    Clock.set(10_001)
    Process.sleep(150)

    # No sweep can have run, so rewinding the clock restores the cache hit.
    Clock.set(0)

    assert {:ok, ^first} = IdempotentPayments.process_payment(pid, @valid_params, "infinity-key")
    assert length(IdempotentPayments.get_payments(pid)) == 1
    assert Process.alive?(pid)
  end

  test "automatic sweeps keep recurring on the configured interval" do
    {:ok, server} =
      IdempotentPayments.start_link(
        clock: &Clock.now/0,
        ttl_ms: 10_000,
        cleanup_interval_ms: 25
      )

    # Two independent rounds. Each round caches its own key at t=0, parks the
    # clock past that key's expiry, and waits for an automatic sweep to purge
    # it. Round two's key only starts existing after round one's sweep has
    # already been observed, so a single non-repeating cleanup cannot cover
    # both rounds: sweeping has to keep happening for the whole test to pass.
    for round <- 1..2 do
      key = "auto-recurring-#{round}"

      Clock.set(0)
      {:ok, cached} = IdempotentPayments.process_payment(server, @valid_params, key)
      Clock.set(10_001)

      reprocessed = await_swept_key(server, key, cached, 10_001, 1_000)
      assert reprocessed.id != cached.id
    end

    # Per round: the originally cached record plus the one reprocessed after
    # the sweep purged the key.
    assert length(IdempotentPayments.get_payments(server)) == 4
    assert Process.alive?(server)
  end

  # Waits, through the public API only, for an automatic sweep to purge `key`.
  # Each probe rewinds the injected clock inside the key's TTL window: while
  # the entry survives the probe is a cache hit that returns the original
  # response and creates no record, so probing is a no-op. Once a sweep has
  # removed the entry the very same probe reprocesses into a brand new record,
  # which is the observable signal that the sweep ran.
  defp await_swept_key(server, key, cached, parked_at, deadline_ms) do
    deadline = System.monotonic_time(:millisecond) + deadline_ms
    poll_for_sweep(server, key, cached, parked_at, deadline)
  end

  defp poll_for_sweep(server, key, cached, parked_at, deadline) do
    Clock.set(0)
    result = IdempotentPayments.process_payment(server, @valid_params, key)
    Clock.set(parked_at)

    case result do
      {:ok, ^cached} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(5)
          poll_for_sweep(server, key, cached, parked_at, deadline)
        else
          flunk("no automatic cleanup sweep purged #{key} before the deadline")
        end

      {:ok, reprocessed} ->
        reprocessed
    end
  end
end
```
