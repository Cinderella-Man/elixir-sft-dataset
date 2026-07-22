defmodule CoalescingPayments do
  @moduledoc """
  An in-memory, idempotent payment processing system with in-flight request coalescing.

  The module exposes a `GenServer` that processes payments through a configurable
  `:processor` function. Requests may carry an *idempotency key*; when several callers
  use the same key while the first request is still being processed, only ONE payment is
  processed and every concurrent waiter receives the same shared result.

  Key properties:

    * the server never blocks inside the processor — the processor runs in a spawned
      worker process which reports its outcome back to the server;
    * completed idempotency entries are cached for `:ttl_ms` milliseconds and returned
      verbatim (same `:id`, same `:created_at`) until they expire;
    * payment records are never removed; only expired idempotency entries are purged by
      the periodic `:cleanup` message;
    * all time comes from the injectable `:clock` function, so tests fully control time.
  """

  use GenServer

  @default_ttl_ms 86_400_000
  @default_cleanup_interval_ms 60_000
  @call_timeout 30_000

  @typedoc "Parameters of a payment request."
  @type params :: map()

  @typedoc "An idempotency key — any term, used as-is as a map key."
  @type idempotency_key :: term()

  @typedoc "A stored payment record."
  @type payment :: %{
          id: String.t(),
          amount: term(),
          currency: term(),
          recipient: term(),
          status: String.t(),
          created_at: integer()
        }

  @typedoc "The result of a payment request."
  @type result :: {:ok, payment()} | {:error, term()}

  # ── Public API ────────────────────────────────────────────────────────────────────

  @doc """
  Starts the payment server.

  Options:

    * `:clock` — zero-arity function returning the current time in milliseconds
      (default: `fn -> System.monotonic_time(:millisecond) end`);
    * `:ttl_ms` — how long a completed idempotency key is remembered (default: `86_400_000`);
    * `:cleanup_interval_ms` — interval of the recurring `:cleanup` message (default:
      `60_000`); `:infinity` disables the scheduling entirely;
    * `:processor` — one-arity function receiving `params` and returning `:ok` or
      `{:error, reason}` (default: `fn _params -> :ok end`);
    * `:name` — forwarded to `GenServer.start_link/3` as the name registration option.

  Any other keys are ignored.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Processes a payment.

  `params` must be a map containing `:amount`, `:currency` and `:recipient`; values are
  never inspected. Invalid params yield `{:error, :invalid_params}` without ever calling
  the processor (and are cached when an idempotency key is supplied).

  With `idempotency_key == nil` every call processes a new payment. With a key, a cached
  completed result is returned as-is, and a request that is already in flight for that key
  is coalesced: the caller waits and receives the single shared result.
  """
  @spec process_payment(GenServer.server(), params(), idempotency_key()) :: result()
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key}, @call_timeout)
  end

  @doc """
  Returns every successful payment record, oldest first (`[]` when there are none).
  """
  @spec get_payments(GenServer.server()) :: [payment()]
  def get_payments(server) do
    GenServer.call(server, :get_payments, @call_timeout)
  end

  @doc """
  Returns `{:ok, payment}` for the payment with the given `id`, or `{:error, :not_found}`.
  """
  @spec get_payment(GenServer.server(), term()) :: {:ok, payment()} | {:error, :not_found}
  def get_payment(server, id) do
    GenServer.call(server, {:get_payment, id}, @call_timeout)
  end

  @doc """
  Returns the number of payment requests currently in flight.

  A coalesced group of waiters on a single idempotency key counts as one. Requests
  rejected as `:invalid_params` never enter this count.
  """
  @spec in_flight_count(GenServer.server()) :: non_neg_integer()
  def in_flight_count(server) do
    GenServer.call(server, :in_flight_count, @call_timeout)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    state = %{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      ttl_ms: Keyword.get(opts, :ttl_ms, @default_ttl_ms),
      cleanup_interval_ms:
        Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      processor: Keyword.get(opts, :processor, fn _params -> :ok end),
      # idempotency key => {:pending, [GenServer.from()]} | {:completed, result, expiry}
      idempotency: %{},
      # reference => {:key, key} | {:nil_key, from}
      in_flight: %{},
      payments: [],
      counter: 0
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:process_payment, params, nil}, from, state) do
    if valid_params?(params) do
      {:noreply, start_work(state, params, {:nil_key, from})}
    else
      {:reply, {:error, :invalid_params}, state}
    end
  end

  def handle_call({:process_payment, params, key}, from, state) do
    now = state.clock.()

    case Map.get(state.idempotency, key) do
      {:pending, waiters} ->
        idempotency = Map.put(state.idempotency, key, {:pending, [from | waiters]})
        {:noreply, %{state | idempotency: idempotency}}

      {:completed, result, expiry} when expiry > now ->
        {:reply, result, state}

      _unseen_or_expired ->
        if valid_params?(params) do
          idempotency = Map.put(state.idempotency, key, {:pending, [from]})
          state = %{state | idempotency: idempotency}
          {:noreply, start_work(state, params, {:key, key})}
        else
          {:reply, {:error, :invalid_params}, cache_result(state, key, {:error, :invalid_params})}
        end
    end
  end

  def handle_call(:get_payments, _from, state) do
    {:reply, Enum.reverse(state.payments), state}
  end

  def handle_call({:get_payment, id}, _from, state) do
    case Enum.find(state.payments, fn payment -> payment.id == id end) do
      nil -> {:reply, {:error, :not_found}, state}
      payment -> {:reply, {:ok, payment}, state}
    end
  end

  def handle_call(:in_flight_count, _from, state) do
    {:reply, map_size(state.in_flight), state}
  end

  def handle_call(_request, _from, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:work_done, ref, outcome, params}, state) do
    case Map.pop(state.in_flight, ref) do
      {nil, _in_flight} ->
        {:noreply, state}

      {target, in_flight} ->
        state = %{state | in_flight: in_flight}
        {result, state} = finalize(state, outcome, params)
        {:noreply, deliver(state, target, result)}
    end
  end

  def handle_info(:cleanup, state) do
    now = state.clock.()

    idempotency =
      state.idempotency
      |> Enum.reject(fn
        {_key, {:completed, _result, expiry}} -> expiry <= now
        {_key, _entry} -> false
      end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | idempotency: idempotency}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast(_message, state) do
    {:noreply, state}
  end

  # ── Internals ─────────────────────────────────────────────────────────────────────

  @spec schedule_cleanup(non_neg_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  @spec valid_params?(term()) :: boolean()
  defp valid_params?(params) when is_map(params) do
    Map.has_key?(params, :amount) and Map.has_key?(params, :currency) and
      Map.has_key?(params, :recipient)
  end

  defp valid_params?(_params), do: false

  # Spawns the worker that runs the processor outside of the server process.
  @spec start_work(map(), params(), {:key, idempotency_key()} | {:nil_key, GenServer.from()}) ::
          map()
  defp start_work(state, params, target) do
    ref = make_ref()
    server = self()
    processor = state.processor

    spawn(fn ->
      outcome =
        try do
          processor.(params)
        rescue
          exception -> {:error, {:exception, Exception.message(exception)}}
        end

      send(server, {:work_done, ref, outcome, params})
    end)

    %{state | in_flight: Map.put(state.in_flight, ref, target)}
  end

  # Turns a processor outcome into a caller-facing result, creating a payment on success.
  @spec finalize(map(), term(), params()) :: {result(), map()}
  defp finalize(state, :ok, params) do
    counter = state.counter + 1

    payment = %{
      id: "pay_#{counter}",
      amount: Map.get(params, :amount),
      currency: Map.get(params, :currency),
      recipient: Map.get(params, :recipient),
      status: "completed",
      created_at: state.clock.()
    }

    state = %{state | counter: counter, payments: [payment | state.payments]}
    {{:ok, payment}, state}
  end

  defp finalize(state, {:error, reason}, _params), do: {{:error, reason}, state}

  defp finalize(state, other, _params), do: {{:error, other}, state}

  # Replies to the caller(s) that were waiting for this unit of work.
  @spec deliver(map(), {:key, idempotency_key()} | {:nil_key, GenServer.from()}, result()) :: map()
  defp deliver(state, {:nil_key, from}, result) do
    GenServer.reply(from, result)
    state
  end

  defp deliver(state, {:key, key}, result) do
    waiters =
      case Map.get(state.idempotency, key) do
        {:pending, waiters} -> waiters
        _other -> []
      end

    Enum.each(waiters, fn from -> GenServer.reply(from, result) end)
    cache_result(state, key, result)
  end

  @spec cache_result(map(), idempotency_key(), result()) :: map()
  defp cache_result(state, key, result) do
    expiry = state.clock.() + state.ttl_ms
    %{state | idempotency: Map.put(state.idempotency, key, {:completed, result, expiry})}
  end
end