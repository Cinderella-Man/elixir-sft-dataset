# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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

## New specification

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
