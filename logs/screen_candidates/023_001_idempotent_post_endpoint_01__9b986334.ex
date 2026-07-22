defmodule IdempotentPayments do
  @moduledoc """
  An in-memory, idempotent payment processing service backed by a `GenServer`.

  The server keeps two pieces of state:

    * `payments` — every payment record that was actually created, keyed by its id.
    * `idempotency` — a cache mapping an idempotency key to the exact response that was
      returned the first time that key was seen, together with an expiry timestamp.

  Calling `process_payment/3` with an idempotency key that is still cached returns the
  original response verbatim and does **not** create a second payment record. Once the
  cached entry expires (after `:ttl_ms` milliseconds), the same key behaves like a fresh
  one and a new payment is created.

  Time is injected through the `:clock` option (a zero-arity function returning
  milliseconds), which makes TTL expiry easy to exercise in tests. Expired idempotency
  entries are purged periodically via `Process.send_after/3`; payment records are never
  removed.

  ## Example

      {:ok, pid} = IdempotentPayments.start_link([])
      params = %{amount: 500, currency: "usd", recipient: "acct_1"}

      {:ok, first} = IdempotentPayments.process_payment(pid, params, "key-1")
      {:ok, ^first} = IdempotentPayments.process_payment(pid, params, "key-1")

      1 = length(IdempotentPayments.get_payments(pid))

  """

  use GenServer

  @default_ttl_ms 86_400_000
  @default_cleanup_interval_ms 60_000
  @required_fields [:amount, :currency, :recipient]

  @type params :: %{optional(atom()) => term()}

  @type response :: %{
          id: String.t(),
          amount: integer(),
          currency: String.t(),
          recipient: String.t(),
          status: String.t(),
          created_at: integer()
        }

  @type payment :: response()

  @type result :: {:ok, response()} | {:error, :invalid_params}

  defmodule State do
    @moduledoc false

    @enforce_keys [:clock, :ttl_ms, :cleanup_interval_ms]
    defstruct [
      :clock,
      :ttl_ms,
      :cleanup_interval_ms,
      payments: %{},
      order: [],
      idempotency: %{},
      counter: 0
    ]
  end

  # ── Public API ──────────────────────────────────────────────────────────────────────

  @doc """
  Starts the payment server.

  ## Options

    * `:clock` — zero-arity function returning the current time in milliseconds.
      Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:ttl_ms` — how long an idempotency key is remembered. Defaults to `86_400_000`
      (24 hours).
    * `:cleanup_interval_ms` — how often expired idempotency entries are purged.
      Defaults to `60_000`. Pass `:infinity` to disable automatic cleanup.

  Any other option (such as `:name`) is forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {server_opts, init_opts} = Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc """
  Processes a payment, optionally under an idempotency key.

  When `idempotency_key` is `nil` a new payment record is always created. When a key is
  given, the first call is processed normally and its response (success *or*
  `{:error, :invalid_params}`) is cached for `:ttl_ms` milliseconds; subsequent calls with
  the same key replay that cached result without creating another payment record.

  `params` must contain `:amount` (integer cents), `:currency` and `:recipient`; otherwise
  `{:error, :invalid_params}` is returned.
  """
  @spec process_payment(GenServer.server(), params(), String.t() | nil) :: result()
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end

  @doc """
  Returns every payment record created so far, oldest first.
  """
  @spec get_payments(GenServer.server()) :: [payment()]
  def get_payments(server) do
    GenServer.call(server, :get_payments)
  end

  @doc """
  Fetches a single payment record by its id.
  """
  @spec get_payment(GenServer.server(), String.t()) :: {:ok, payment()} | {:error, :not_found}
  def get_payment(server, id) do
    GenServer.call(server, {:get_payment, id})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────────────

  @impl GenServer
  @spec init(keyword()) :: {:ok, State.t()}
  def init(opts) do
    state = %State{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      ttl_ms: Keyword.get(opts, :ttl_ms, @default_ttl_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    }

    schedule_cleanup(state.cleanup_interval_ms)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:process_payment, params, idempotency_key}, _from, state) do
    now = state.clock.()

    case cached_response(state, idempotency_key, now) do
      {:ok, cached} ->
        {:reply, cached, state}

      :miss ->
        {result, state} = do_process(state, params, now)
        state = maybe_cache(state, idempotency_key, result, now)
        {:reply, result, state}
    end
  end

  def handle_call(:get_payments, _from, state) do
    payments =
      state.order
      |> Enum.reverse()
      |> Enum.map(&Map.fetch!(state.payments, &1))

    {:reply, payments, state}
  end

  def handle_call({:get_payment, id}, _from, state) do
    case Map.fetch(state.payments, id) do
      {:ok, payment} -> {:reply, {:ok, payment}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    idempotency =
      state.idempotency
      |> Enum.reject(fn {_key, entry} -> expired?(entry, now) end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %State{state | idempotency: idempotency}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  # ── Internals ───────────────────────────────────────────────────────────────────────

  @spec do_process(State.t(), params(), integer()) :: {result(), State.t()}
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

      state = %State{
        state
        | counter: counter,
          payments: Map.put(state.payments, id, response),
          order: [id | state.order]
      }

      {{:ok, response}, state}
    else
      {{:error, :invalid_params}, state}
    end
  end

  @spec valid_params?(term()) :: boolean()
  defp valid_params?(params) when is_map(params) do
    Enum.all?(@required_fields, &Map.has_key?(params, &1)) and
      is_integer(Map.get(params, :amount)) and
      is_binary(Map.get(params, :currency)) and
      is_binary(Map.get(params, :recipient))
  end

  defp valid_params?(_params), do: false

  @spec cached_response(State.t(), String.t() | nil, integer()) :: {:ok, result()} | :miss
  defp cached_response(_state, nil, _now), do: :miss

  defp cached_response(state, key, now) do
    case Map.fetch(state.idempotency, key) do
      {:ok, entry} ->
        if expired?(entry, now), do: :miss, else: {:ok, entry.response}

      :error ->
        :miss
    end
  end

  @spec maybe_cache(State.t(), String.t() | nil, result(), integer()) :: State.t()
  defp maybe_cache(state, nil, _result, _now), do: state

  defp maybe_cache(state, key, result, now) do
    entry = %{response: result, expires_at: expires_at(now, state.ttl_ms)}

    %State{state | idempotency: Map.put(state.idempotency, key, entry)}
  end

  @spec expires_at(integer(), non_neg_integer() | :infinity) :: integer() | :infinity
  defp expires_at(_now, :infinity), do: :infinity
  defp expires_at(now, ttl_ms), do: now + ttl_ms

  @spec expired?(map(), integer()) :: boolean()
  defp expired?(%{expires_at: :infinity}, _now), do: false
  defp expired?(%{expires_at: expires_at}, now), do: now >= expires_at

  @spec schedule_cleanup(pos_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :cleanup, interval_ms)
    :ok
  end
end