Implement the `handle_info/2` GenServer callbacks for `CoalescingPayments`. There
are four clauses to fill in; together they receive the messages the server sends
to itself and drive the coalescing and cleanup behaviour.

1. `{:work_done, {:nil_req, ref}, params, outcome}` — a spawned worker for a
   request that had **no** idempotency key has finished. Pop `ref` out of
   `nil_pending` to recover the single waiting `from`. Run the outcome through
   `finalize/3` (which mints the response and appends the payment record on
   success, threading the updated state). Reply to that `from` (if one is still
   present) with the result via `GenServer.reply/2`, and return the state with
   `ref` removed from `nil_pending`.

2. `{:work_done, {:key, key}, params, outcome}` — a spawned worker for a
   **keyed** request has finished. Run the outcome through `finalize/3`, compute
   an `expiry` of `now + ttl_ms` using the clock, and pop the current entry for
   `key`. That entry should be `{:pending, froms}`, holding every caller that
   coalesced onto this key; extract the list of `froms` (default to `[]` if the
   entry is missing or not pending). Store the key as
   `{:completed, result, expiry}` so future callers hit the cache, reply the
   single shared result to **every** coalesced `from`, and return the updated
   state.

3. `:cleanup` — the periodic purge fired by `schedule_cleanup/1`. Using the
   current time from the clock, keep only idempotency entries that are still
   live: `{:completed, _r, expiry}` entries whose `expiry` is still in the
   future, and any `{:pending, _}` entries (in-flight work is never purged).
   Reschedule the next cleanup with `schedule_cleanup/1` and return the state
   with the filtered `idempotency_keys`.

4. `_msg` — ignore any other message and leave the state unchanged.

```elixir
defmodule CoalescingPayments do
  @moduledoc """
  A GenServer that simulates an idempotent payment system with in-flight request
  coalescing: concurrent callers sharing an idempotency key trigger the processor
  exactly once and all receive the same result. Completed keys are cached with a
  TTL; payment records are never removed.
  """

  use GenServer

  @default_ttl_ms 86_400_000
  @default_cleanup_interval_ms 60_000

  @typedoc "A payment response record."
  @type response :: %{
          id: String.t(),
          amount: integer(),
          currency: String.t(),
          recipient: String.t(),
          status: String.t(),
          created_at: integer()
        }

  @typedoc "The result returned to a caller of `process_payment/3`."
  @type result :: {:ok, response()} | {:error, term()}

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the payment server.

  Accepts `:clock`, `:ttl_ms`, `:cleanup_interval_ms`, `:processor` and the
  usual `:name` option forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Processes a payment, coalescing concurrent in-flight requests that share the
  same `idempotency_key`.

  Returns `{:ok, response}` or `{:error, reason}`. When `idempotency_key` is
  `nil` every call runs the processor independently.
  """
  @spec process_payment(GenServer.server(), map(), String.t() | nil) :: result()
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key}, 30_000)
  end

  @doc "Returns all payment records, oldest first."
  @spec get_payments(GenServer.server()) :: [response()]
  def get_payments(server), do: GenServer.call(server, :get_payments)

  @doc "Returns `{:ok, payment}` for `id` or `{:error, :not_found}`."
  @spec get_payment(GenServer.server(), String.t()) ::
          {:ok, response()} | {:error, :not_found}
  def get_payment(server, id), do: GenServer.call(server, {:get_payment, id})

  @doc "Returns the number of payments currently being processed."
  @spec in_flight_count(GenServer.server()) :: non_neg_integer()
  def in_flight_count(server), do: GenServer.call(server, :in_flight_count)

  # --------------------------------------------------------------------------
  # Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      ttl_ms: Keyword.get(opts, :ttl_ms, @default_ttl_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      processor: Keyword.get(opts, :processor, fn _params -> :ok end),
      counter: 0,
      payments: [],
      # key => {:completed, result, expiry} | {:pending, [from]}
      idempotency_keys: %{},
      # ref => from  (in-flight requests without an idempotency key)
      nil_pending: %{}
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:process_payment, params, nil}, from, state) do
    if valid_params?(params) do
      ref = make_ref()
      start_work(state.processor, params, {:nil_req, ref})
      {:noreply, %{state | nil_pending: Map.put(state.nil_pending, ref, from)}}
    else
      {:reply, {:error, :invalid_params}, state}
    end
  end

  def handle_call({:process_payment, params, key}, from, state) do
    now = state.clock.()

    case Map.get(state.idempotency_keys, key) do
      {:completed, result, expiry} when expiry > now ->
        {:reply, result, state}

      {:pending, froms} ->
        keys = Map.put(state.idempotency_keys, key, {:pending, [from | froms]})
        {:noreply, %{state | idempotency_keys: keys}}

      _ ->
        if valid_params?(params) do
          start_work(state.processor, params, {:key, key})
          keys = Map.put(state.idempotency_keys, key, {:pending, [from]})
          {:noreply, %{state | idempotency_keys: keys}}
        else
          result = {:error, :invalid_params}
          expiry = now + state.ttl_ms
          keys = Map.put(state.idempotency_keys, key, {:completed, result, expiry})
          {:reply, result, %{state | idempotency_keys: keys}}
        end
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

  def handle_call(:in_flight_count, _from, state) do
    key_pending =
      Enum.count(state.idempotency_keys, fn {_k, v} -> match?({:pending, _}, v) end)

    {:reply, key_pending + map_size(state.nil_pending), state}
  end

  def handle_info({:work_done, {:nil_req, ref}, params, outcome}, state) do
    # TODO
  end

  # --------------------------------------------------------------------------
  # Internals
  # --------------------------------------------------------------------------

  defp start_work(processor, params, tag) do
    server = self()

    spawn(fn ->
      outcome =
        try do
          processor.(params)
        rescue
          e -> {:error, {:exception, Exception.message(e)}}
        end

      send(server, {:work_done, tag, params, outcome})
    end)
  end

  defp finalize(state, params, :ok) do
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

    state = %{state | counter: counter, payments: [response | state.payments]}
    {{:ok, response}, state}
  end

  defp finalize(state, _params, {:error, reason}) do
    {{:error, reason}, state}
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