Implement the GenServer `handle_call/3` callback for `StrictIdempotentPayments`.
It handles four kinds of synchronous requests and must reply via the standard
`{:reply, result, new_state}` tuple. It may use the existing private helpers
`do_process/2` (which returns `{result, new_state}` and handles validation,
counter/id assignment, and appending payment records) and `fingerprint/1`, plus
the clock in `state.clock`.

Behaviour, clause by clause:

1. `{:process_payment, params, nil}` — no idempotency key. Always process the
   params via `do_process/2` and reply with whatever result it returns, using the
   updated state.

2. `{:process_payment, params, key}` — with an idempotency key. Read the current
   time from `state.clock` and compute the params `fingerprint/1`. Look up `key`
   in `state.idempotency_keys` (stored as `{result, stored_fingerprint, expiry}`):
   - If an entry exists and is not expired (`expiry > now`): if its stored
     fingerprint matches the current one, reply with the cached `result` and leave
     state unchanged; otherwise reply `{:error, :idempotency_key_conflict}` and
     leave state unchanged (do not create a record, do not mutate the entry).
   - Otherwise (unseen or expired): process the params via `do_process/2`, compute
     `expiry = now + state.ttl_ms`, store `{result, fingerprint, expiry}` under
     `key` in `idempotency_keys`, and reply with `result` and the updated state.

3. `:get_payments` — reply with all payment records oldest-first. Records are
   stored newest-first in `state.payments`, so reverse them.

4. `{:get_payment, id}` — find the record whose `id` matches in `state.payments`;
   reply `{:ok, payment}` when found, or `{:error, :not_found}` otherwise. State
   is unchanged.

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

  def handle_call({:process_payment, params, nil}, _from, state) do
    # TODO
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

  # Arms the next periodic purge (when enabled) and returns the state unchanged,
  # so it can be threaded through `init/1` and `handle_info/2`.
  defp schedule_cleanup(%{cleanup_interval_ms: :infinity} = state), do: state

  defp schedule_cleanup(%{cleanup_interval_ms: interval} = state) when is_integer(interval) do
    Process.send_after(self(), :cleanup, interval)
    state
  end
end
```