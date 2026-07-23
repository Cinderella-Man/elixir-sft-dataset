# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `schedule_cleanup` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

Write me an Elixir GenServer module called `StrictIdempotentPayments` that simulates an idempotent payment processing system with in-memory storage **and request-fingerprint conflict detection**. The key behavioral difference from a naive idempotent endpoint: replaying an idempotency key with a *different request body* is treated as a client error rather than silently returning the original cached response.

Public API:

- `StrictIdempotentPayments.start_link(opts)` accepting `:clock` (zero-arity ms clock, default `fn -> System.monotonic_time(:millisecond) end`), `:ttl_ms` (default 86,400,000), and `:cleanup_interval_ms` (default 60,000; `:infinity` disables the periodic `:cleanup` purge via `Process.send_after`).

- `StrictIdempotentPayments.process_payment(server, params, idempotency_key \\ nil)` where `params` is a map with `:amount` (integer cents), `:currency` (string), `:recipient` (string). Each stored idempotency entry records the cached result, a **fingerprint** of the request params (compute it deterministically, e.g. `:erlang.phash2(params)`), and an expiry timestamp. An entry stored at clock time `T` expires at `T + ttl_ms`, and counts as expired once the clock reaches that timestamp: it is valid only while the current clock reading is strictly less than `T + ttl_ms` (so a replay at exactly `T + ttl_ms` is processed fresh, not served from cache). Semantics:
  1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
  2. If the key has been seen and is not expired **and the current params fingerprint matches the stored one**, return the exact cached result.
  3. If the key has been seen and is not expired **but the params fingerprint differs**, return `{:error, :idempotency_key_conflict}` — do NOT return the cached response, do NOT create a new record, and do NOT mutate the stored entry.
  4. If the key is expired or unseen, process normally (fingerprint the new params), cache the result under the key with a TTL, and return it.
  5. If required fields are missing, return `{:error, :invalid_params}`; when a key was provided, cache that error result along with its fingerprint (so a same-params replay returns the same error, while a different-params replay under that key is a conflict).

  A successful `response` map contains `:id` (counter-based unique string; the first record created is `"pay_1"`, the next `"pay_2"`, and so on — the counter advances only when a record is actually created), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (clock timestamp).

- `StrictIdempotentPayments.get_payments(server)` returns all payment records as a list, oldest first (an empty list when there are none).
- `StrictIdempotentPayments.get_payment(server, id)` returns `{:ok, payment}` or `{:error, :not_found}`.

The periodic `:cleanup` removes only expired idempotency entries (an entry is expired once the clock has reached its expiry timestamp); payment records are never removed. Sending `:cleanup` to the server must never crash it. Use only the OTP standard library. Give me the complete module in a single file.

## The module with `schedule_cleanup` missing

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

    {:ok, schedule_cleanup(state)}
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

    {:noreply, schedule_cleanup(%{state | idempotency_keys: kept})}
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

  defp schedule_cleanup(%{cleanup_interval_ms: :infinity} = state) do
    # TODO
  end
end
```

Reply with `schedule_cleanup` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
