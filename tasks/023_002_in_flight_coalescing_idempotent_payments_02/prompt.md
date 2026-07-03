Implement the `handle_call/3` GenServer callback (all of its clauses). It handles
every synchronous request sent by the public API and must cover the following
cases:

- `{:process_payment, params, nil}` (no idempotency key): validate `params` with
  `valid_params?/1`. If valid, create a fresh `make_ref/0`, kick off the processor
  in a spawned process via `start_work/3` tagged `{:nil_req, ref}`, remember the
  caller by storing `ref => from` in `nil_pending`, and return `{:noreply, state}`
  (the caller is replied to later from `handle_info/2`). If invalid, reply
  immediately with `{:error, :invalid_params}` and leave the state unchanged.

- `{:process_payment, params, key}` (with an idempotency key): read the current
  time via `state.clock.()`. Look up `key` in `idempotency_keys`:
  - `{:completed, result, expiry}` that has not expired (`expiry > now`): reply
    with the cached `result` without running the processor.
  - `{:pending, froms}` (processing already in flight): register this caller by
    prepending `from` to `froms`, and return `{:noreply, ...}` so it blocks until
    the shared result is ready.
  - anything else (unseen or expired): if `params` are valid, start the processor
    via `start_work/3` tagged `{:key, key}`, mark the key `{:pending, [from]}`, and
    return `{:noreply, ...}`. If the params are invalid, build
    `{:error, :invalid_params}`, cache it as a completed entry with expiry
    `now + state.ttl_ms`, and reply with that error.

- `:get_payments`: reply with all payment records oldest first
  (`Enum.reverse(state.payments)`).

- `{:get_payment, id}`: find the payment whose `id` matches and reply
  `{:ok, payment}`, or `{:error, :not_found}` when there is none.

- `:in_flight_count`: reply with the number of in-flight payments — the count of
  `idempotency_keys` entries that are `{:pending, _}` plus `map_size(nil_pending)`.

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
  def handle_call(request, from, state) do
    # TODO
  end

  @impl true
  def handle_info({:work_done, {:nil_req, ref}, params, outcome}, state) do
    {from, nil_pending} = Map.pop(state.nil_pending, ref)
    {result, state} = finalize(state, params, outcome)
    if from, do: GenServer.reply(from, result)
    {:noreply, %{state | nil_pending: nil_pending}}
  end

  def handle_info({:work_done, {:key, key}, params, outcome}, state) do
    {result, state} = finalize(state, params, outcome)
    expiry = state.clock.() + state.ttl_ms
    {entry, keys} = Map.pop(state.idempotency_keys, key)

    froms =
      case entry do
        {:pending, fs} -> fs
        _ -> []
      end

    keys = Map.put(keys, key, {:completed, result, expiry})
    Enum.each(froms, fn from -> GenServer.reply(from, result) end)
    {:noreply, %{state | idempotency_keys: keys}}
  end

  def handle_info(:cleanup, state) do
    now = state.clock.()

    kept =
      state.idempotency_keys
      |> Enum.filter(fn
        {_k, {:completed, _r, expiry}} -> expiry > now
        {_k, {:pending, _}} -> true
      end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | idempotency_keys: kept}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

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