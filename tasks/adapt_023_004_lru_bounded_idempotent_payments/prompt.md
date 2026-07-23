# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

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

## New specification

# Design Brief: `BoundedIdempotentPayments`

## Problem

We need an Elixir GenServer module called `BoundedIdempotentPayments` that simulates an idempotent payment processing system with in-memory storage. Unlike a conventional idempotency store that remembers keys for a fixed time window and sweeps expired ones, this store's idempotency layer must be **capacity-bounded with LRU eviction instead of TTL expiry**: it keeps at most a configured number of idempotency keys, and when a brand-new key would overflow that budget, the least-recently-used key is evicted first.

## Constraints

- There is no clock-based expiry and no periodic cleanup.
- Recency must be tracked deterministically with an internal monotonic access counter (a "tick"), NOT wall-clock time — every insert and every cache hit advances the tick and stamps the touched key.
- Payment records are never evicted — only idempotency keys are bounded.
- Use only the OTP standard library.
- Deliver the complete module in a single file.

## Required Interface

1. `BoundedIdempotentPayments.start_link(opts)` accepting:
   - `:max_keys` — a positive integer, the maximum number of idempotency keys retained; default 1000. Raise `ArgumentError` if it is not a positive integer.
   - `:clock` — a zero-arity ms clock used only for the `:created_at` timestamp; default `fn -> System.monotonic_time(:millisecond) end`.

2. `BoundedIdempotentPayments.process_payment(server, params, idempotency_key \\ nil)` where `params` is a map with `:amount` (integer cents), `:currency` (string), `:recipient` (string). Semantics:
   1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
   2. If the key is present in the store, return the exact cached result and **refresh its recency** (mark it most-recently-used).
   3. If the key is absent (never seen or previously evicted), process the payment. If the store is already at `:max_keys`, evict the least-recently-used key first, then insert this key as most-recently-used. Return the result.
   4. If required fields are missing, return `{:error, :invalid_params}`; when a key was provided, cache that error result under the key too (it occupies a slot and participates in LRU just like a success).

   A successful `response` map contains `:id` (counter-based unique string like `"pay_1"`), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (clock timestamp).

3. `BoundedIdempotentPayments.get_payments(server)` returns all payment records (oldest first).

4. `BoundedIdempotentPayments.get_payment(server, id)` returns `{:ok, payment}` or `{:error, :not_found}`.

5. `BoundedIdempotentPayments.keys_by_recency(server)` returns the currently retained idempotency keys ordered least-recently-used first (for inspection/testing).

## Acceptance Criteria

- `start_link/1` honors `:max_keys` (default 1000) and raises `ArgumentError` when `:max_keys` is not a positive integer; `:clock` defaults to `fn -> System.monotonic_time(:millisecond) end` and is used only for the `:created_at` timestamp.
- A `nil` idempotency key always creates a new payment record and returns `{:ok, response}`.
- A present key returns the exact cached result and marks that key most-recently-used.
- An absent key processes the payment, and when the store is already at `:max_keys` it evicts the least-recently-used key before inserting the new key as most-recently-used.
- Missing required fields yield `{:error, :invalid_params}`, and when a key was provided that error result is cached under the key, occupying a slot and participating in LRU like a success.
- Recency is driven by the internal monotonic tick (advanced and stamped on every insert and every cache hit), never wall-clock time.
- A successful `response` contains `:id` (counter-based unique string like `"pay_1"`), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (clock timestamp).
- `get_payments/1` returns records oldest first; `get_payment/2` returns `{:ok, payment}` or `{:error, :not_found}`; `keys_by_recency/1` returns retained keys least-recently-used first.
- Payment records are never evicted — only idempotency keys are bounded — and the module uses only the OTP standard library, delivered as one complete file.
