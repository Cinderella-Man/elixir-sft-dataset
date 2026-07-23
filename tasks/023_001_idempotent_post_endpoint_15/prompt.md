# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `get_payments`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# `IdempotentPayments` — idempotent in-memory payment GenServer

Implement an Elixir GenServer module `IdempotentPayments` simulating an idempotent payment processing system with in-memory storage. Single file, complete module. No external dependencies — OTP standard library only.

**`IdempotentPayments.start_link(opts)`**
- Starts the process.
- Accepts `:clock` — a zero-arity function returning the current time in milliseconds; default `fn -> System.monotonic_time(:millisecond) end`.
- Accepts `:ttl_ms` — how long idempotency keys are remembered; default 86,400,000 (24 hours).
- Accepts `:cleanup_interval_ms` — how often expired idempotency entries are purged via `Process.send_after`; default 60,000. Pass `:infinity` to disable automatic cleanup.

**`IdempotentPayments.process_payment(server, params, idempotency_key \\ nil)`**
- `params` is a map containing `:amount` (integer, cents), `:currency` (string), and `:recipient` (string).
- Behavior:
  1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
  2. If `idempotency_key` is provided, seen before, and not yet expired, return `{:ok, response}` with the exact same response map returned the first time, without creating a duplicate payment record. This holds even if the replay carries different `params`.
  3. If `idempotency_key` is provided but has expired or was never seen, process the payment normally, cache the response keyed by the idempotency key with a fresh TTL, and return `{:ok, response}`.
  4. If required fields are missing from `params`, return `{:error, :invalid_params}`. If an idempotency key was provided, cache this error response too so replaying the same key returns the same error (even if the replay carries valid `params`), and no payment record is created.
- **Expiry:** an entry cached at clock time `T` expires at `T + ttl_ms`. It counts as a cache hit only while the current clock time is strictly less than that expiry; at exactly the expiry timestamp and after, the key is treated as expired. With `ttl_ms` of 10,000, a key cached at `t = 0` is still a hit at `t = 9_999` but is expired at `t = 10_000`.
- **`response` map fields:** `:id` (unique payment id string — see ID rule), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (the timestamp read from the clock at the moment the payment is processed).

**`IdempotentPayments.get_payments(server)`**
- Returns a list of all payment records stored, in creation order (oldest first), for test assertions about how many records were actually created.

**`IdempotentPayments.get_payment(server, id)`**
- Returns `{:ok, payment}` or `{:error, :not_found}`.

**Internal state**
- Each idempotency key entry stores the full response and the expiry timestamp.

**Cleanup**
- Periodic cleanup is triggered by a `:cleanup` message handled via `handle_info`.
- Removes only expired idempotency entries: an entry whose expiry timestamp is less than or equal to the current clock time counts as expired and is removed; one whose expiry is still strictly greater than the current time is kept.
- Payment records themselves are never cleaned up.

**Payment IDs**
- Sequential counter-based strings: `"pay_1"`, `"pay_2"`, `"pay_3"`, and so on.
- First payment record created is `"pay_1"`; the counter increments by exactly one per record in creation order.
- The counter is consumed only when a new payment record is actually created — idempotent cache hits and cached errors must not consume a number.

## The module with `get_payments` missing

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

  def get_payments(server) do
    # TODO
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

Output only `get_payments` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
