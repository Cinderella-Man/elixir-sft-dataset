# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

Write me an Elixir GenServer module called `BoundedIdempotentPayments` that simulates an idempotent payment processing system with in-memory storage where the idempotency store is **capacity-bounded with LRU eviction instead of TTL expiry**. Rather than remembering keys for a fixed time window and sweeping expired ones, the store keeps at most a configured number of idempotency keys; when a brand-new key would overflow that budget, the least-recently-used key is evicted first. There is no clock-based expiry and no periodic cleanup.

Public API:

- `BoundedIdempotentPayments.start_link(opts)` accepting `:max_keys` (a positive integer, the maximum number of idempotency keys retained; default 1000 — raise `ArgumentError` if it is not a positive integer) and `:clock` (zero-arity ms clock used only for the `:created_at` timestamp, default `fn -> System.monotonic_time(:millisecond) end`).

- `BoundedIdempotentPayments.process_payment(server, params, idempotency_key \\ nil)` where `params` is a map with `:amount` (integer cents), `:currency` (string), `:recipient` (string). Semantics:
  1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
  2. If the key is present in the store, return the exact cached result and **refresh its recency** (mark it most-recently-used).
  3. If the key is absent (never seen or previously evicted), process the payment. If the store is already at `:max_keys`, evict the least-recently-used key first, then insert this key as most-recently-used. Return the result.
  4. If required fields are missing, return `{:error, :invalid_params}`; when a key was provided, cache that error result under the key too (it occupies a slot and participates in LRU just like a success).

  Recency must be tracked deterministically with an internal monotonic access counter (a "tick"), NOT wall-clock time — every insert and every cache hit advances the tick and stamps the touched key. A successful `response` map contains `:id` (counter-based unique string like `"pay_1"`), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (clock timestamp).

- `BoundedIdempotentPayments.get_payments(server)` returns all payment records (oldest first).
- `BoundedIdempotentPayments.get_payment(server, id)` returns `{:ok, payment}` or `{:error, :not_found}`.
- `BoundedIdempotentPayments.keys_by_recency(server)` returns the currently retained idempotency keys ordered least-recently-used first (for inspection/testing).

Payment records are never evicted — only idempotency keys are bounded. Use only the OTP standard library. Give me the complete module in a single file.

## The buggy module

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

    {:error, state}
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

## Failing test report

```
12 of 12 test(s) failed:

  * test raises for invalid :max_keys
      no match of right hand side value:
      
          {:error,
           %{
             tick: 0,
             counter: 0,
             max_keys: 1000,
             clock: &BoundedIdempotentPaymentsTest.Clock.now/0,
             payments: [],
             idempotency_keys: %{}
           }}
      

  * test processes a payment and returns a response
      no match of right hand side value:
      
          {:error,
           %{
             tick: 0,
             counter: 0,
             max_keys: 1000,
             clock: &BoundedIdempotentPaymentsTest.Clock.now/0,
             payments: [],
             idempotency_keys: %{}
           }}
      

  * test requests without idempotency key always create new records
      no match of right hand side value:
      
          {:error,
           %{
             tick: 0,
             counter: 0,
             max_keys: 1000,
             clock: &BoundedIdempotentPaymentsTest.Clock.now/0,
             payments: [],
             idempotency_keys: %{}
           }}
      

  * test same key returns cached result without a duplicate record
      no match of right hand side value:
      
          {:error,
           %{
             tick: 0,
             counter: 0,
             max_keys: 1000,
             clock: &BoundedIdempotentPaymentsTest.Clock.now/0,
             payments: [],
             idempotency_keys: %{}
           }}
      

  (…8 more)
```
