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

Hey — I need you to write me an Elixir GenServer module called `StrictIdempotentPayments`. The idea is to simulate an idempotent payment processing system with in-memory storage, but with a twist I care about a lot: request-fingerprint conflict detection. Here's the key behavioral difference from a naive idempotent endpoint — if someone replays an idempotency key with a *different request body*, I want that treated as a client error rather than silently returning the original cached response.

For the public API, start with `StrictIdempotentPayments.start_link(opts)`. It should accept `:clock` (a zero-arity ms clock, defaulting to `fn -> System.monotonic_time(:millisecond) end`), `:ttl_ms` (default 86,400,000), and `:cleanup_interval_ms` (default 60,000; passing `:infinity` disables the periodic `:cleanup` purge that otherwise runs via `Process.send_after`).

Then I need `StrictIdempotentPayments.process_payment(server, params, idempotency_key \\ nil)`, where `params` is a map carrying `:amount` (integer cents), `:currency` (string), and `:recipient` (string). Each stored idempotency entry should record the cached result, a fingerprint of the request params (compute it deterministically, e.g. `:erlang.phash2(params)`), and an expiry timestamp. An entry stored at clock time `T` expires at `T + ttl_ms`, and it counts as expired once the clock reaches that timestamp — so it's valid only while the current clock reading is strictly less than `T + ttl_ms`, meaning a replay at exactly `T + ttl_ms` gets processed fresh rather than served from cache. The semantics I want are:

1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
2. If the key has been seen and isn't expired and the current params fingerprint matches the stored one, return the exact cached result.
3. If the key has been seen and isn't expired but the params fingerprint differs, return `{:error, :idempotency_key_conflict}` — don't return the cached response, don't create a new record, and don't mutate the stored entry.
4. If the key is expired or unseen, process it normally (fingerprint the new params), cache the result under the key with a TTL, and return it.
5. If required fields are missing, return `{:error, :invalid_params}`; and when a key was provided, cache that error result along with its fingerprint — so a same-params replay returns the same error, while a different-params replay under that key is a conflict.

A successful `response` map should contain `:id` (a counter-based unique string; the first record created is `"pay_1"`, the next `"pay_2"`, and so on — the counter advances only when a record is actually created), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (the clock timestamp).

I also want `StrictIdempotentPayments.get_payments(server)` to return all payment records as a list, oldest first (an empty list when there are none), and `StrictIdempotentPayments.get_payment(server, id)` to return `{:ok, payment}` or `{:error, :not_found}`.

The periodic `:cleanup` should remove only expired idempotency entries (again, an entry is expired once the clock has reached its expiry timestamp); payment records must never be removed. And sending `:cleanup` to the server must never crash it. Please use only the OTP standard library, and give me the complete module in a single file.
