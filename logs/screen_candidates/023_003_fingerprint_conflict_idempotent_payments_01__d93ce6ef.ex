defmodule StrictIdempotentPayments do
  @moduledoc """
  An in-memory, idempotent payment processor with request-fingerprint conflict detection.

  Payments are recorded in a monotonically growing list, keyed by a counter-based id such as
  `"pay_1"`. When a caller supplies an idempotency key, the server stores the produced result
  together with a deterministic fingerprint of the request params and an expiry timestamp.

  Replaying a live idempotency key behaves as follows:

    * same params (matching fingerprint) -> the exact cached result is returned;
    * different params (fingerprint mismatch) -> `{:error, :idempotency_key_conflict}` is
      returned. No cached response is disclosed, no new payment record is created, and the
      stored entry is left untouched.

  Expired or unseen keys are processed normally and (re)cached. Validation failures are cached
  as well, so that a same-params replay yields the same `{:error, :invalid_params}` result while
  a different-params replay under the same key is a conflict.

  A periodic `:cleanup` message purges only expired idempotency entries; payment records are
  never removed.

  Only the OTP standard library is used.
  """

  use GenServer

  @default_ttl_ms 86_400_000
  @default_cleanup_interval_ms 60_000

  @typedoc "Payment request parameters."
  @type params :: %{optional(atom()) => term()}

  @typedoc "A successfully created payment record."
  @type payment :: %{
          id: String.t(),
          amount: integer(),
          currency: String.t(),
          recipient: String.t(),
          status: String.t(),
          created_at: integer()
        }

  @typedoc "The result of a payment attempt."
  @type result ::
          {:ok, payment()}
          | {:error, :invalid_params}
          | {:error, :idempotency_key_conflict}

  defmodule State do
    @moduledoc false

    defstruct clock: nil,
              ttl_ms: 86_400_000,
              cleanup_interval_ms: 60_000,
              counter: 0,
              payments: [],
              index: %{},
              keys: %{}
  end

  # ----------------------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------------------

  @doc """
  Starts the payment server.

  Options:

    * `:clock` - a zero-arity function returning milliseconds. Defaults to
      `fn -> System.monotonic_time(:millisecond) end`.
    * `:ttl_ms` - lifetime of an idempotency entry in milliseconds (default `86_400_000`).
    * `:cleanup_interval_ms` - interval of the periodic purge of expired idempotency entries
      (default `60_000`). Use `:infinity` to disable the periodic purge entirely.

  Any other option (for example `:name`) is forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {server_opts, init_opts} = Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc """
  Processes a payment request.

  `params` must be a map containing `:amount` (integer cents), `:currency` (string) and
  `:recipient` (string). Missing or malformed fields yield `{:error, :invalid_params}`.

  When `idempotency_key` is `nil` a new payment record is always created. Otherwise the key is
  consulted: a live entry whose stored fingerprint matches the current params replays the cached
  result verbatim; a live entry whose fingerprint differs returns
  `{:error, :idempotency_key_conflict}` without creating or mutating anything; an expired or
  unseen key is processed normally and cached with a fresh TTL.
  """
  @spec process_payment(GenServer.server(), params(), String.t() | nil) :: result()
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end

  @doc """
  Returns every payment record ever created, oldest first.
  """
  @spec get_payments(GenServer.server()) :: [payment()]
  def get_payments(server) do
    GenServer.call(server, :get_payments)
  end

  @doc """
  Fetches a single payment record by its id, e.g. `"pay_1"`.
  """
  @spec get_payment(GenServer.server(), String.t()) :: {:ok, payment()} | {:error, :not_found}
  def get_payment(server, id) do
    GenServer.call(server, {:get_payment, id})
  end

  # ----------------------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %State{
      clock: clock,
      ttl_ms: ttl_ms,
      cleanup_interval_ms: cleanup_interval_ms
    }

    schedule_cleanup(state)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:process_payment, params, idempotency_key}, _from, state) do
    do_process(params, idempotency_key, state)
  end

  def handle_call(:get_payments, _from, state) do
    {:reply, Enum.reverse(state.payments), state}
  end

  def handle_call({:get_payment, id}, _from, state) do
    case Map.fetch(state.index, id) do
      {:ok, payment} -> {:reply, {:ok, payment}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = now(state)

    keys =
      state.keys
      |> Enum.reject(fn {_key, entry} -> expired?(entry, now) end)
      |> Map.new()

    state = %State{state | keys: keys}
    schedule_cleanup(state)

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  # ----------------------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------------------

  @spec do_process(params(), String.t() | nil, State.t()) ::
          {:reply, result(), State.t()}
  defp do_process(params, nil, state) do
    {result, state} = execute(params, state)
    {:reply, result, state}
  end

  defp do_process(params, key, state) do
    now = now(state)
    fingerprint = fingerprint(params)

    case Map.fetch(state.keys, key) do
      {:ok, entry} ->
        cond do
          expired?(entry, now) -> store_and_reply(params, key, fingerprint, state)
          entry.fingerprint == fingerprint -> {:reply, entry.result, state}
          true -> {:reply, {:error, :idempotency_key_conflict}, state}
        end

      :error ->
        store_and_reply(params, key, fingerprint, state)
    end
  end

  @spec store_and_reply(params(), String.t(), integer(), State.t()) ::
          {:reply, result(), State.t()}
  defp store_and_reply(params, key, fingerprint, state) do
    {result, state} = execute(params, state)

    entry = %{
      result: result,
      fingerprint: fingerprint,
      expires_at: now(state) + state.ttl_ms
    }

    {:reply, result, %State{state | keys: Map.put(state.keys, key, entry)}}
  end

  @spec execute(params(), State.t()) :: {result(), State.t()}
  defp execute(params, state) do
    case validate(params) do
      {:ok, {amount, currency, recipient}} ->
        counter = state.counter + 1
        id = "pay_" <> Integer.to_string(counter)

        payment = %{
          id: id,
          amount: amount,
          currency: currency,
          recipient: recipient,
          status: "completed",
          created_at: now(state)
        }

        state = %State{
          state
          | counter: counter,
            payments: [payment | state.payments],
            index: Map.put(state.index, id, payment)
        }

        {{:ok, payment}, state}

      :error ->
        {{:error, :invalid_params}, state}
    end
  end

  @spec validate(term()) :: {:ok, {integer(), String.t(), String.t()}} | :error
  defp validate(params) when is_map(params) do
    with {:ok, amount} when is_integer(amount) <- Map.fetch(params, :amount),
         {:ok, currency} when is_binary(currency) <- Map.fetch(params, :currency),
         {:ok, recipient} when is_binary(recipient) <- Map.fetch(params, :recipient),
         true <- currency != "" and recipient != "" do
      {:ok, {amount, currency, recipient}}
    else
      _other -> :error
    end
  end

  defp validate(_params), do: :error

  @spec fingerprint(term()) :: integer()
  defp fingerprint(params), do: :erlang.phash2(params)

  @spec expired?(map(), integer()) :: boolean()
  defp expired?(%{expires_at: expires_at}, now), do: now >= expires_at

  @spec now(State.t()) :: integer()
  defp now(%State{clock: clock}), do: clock.()

  @spec schedule_cleanup(State.t()) :: :ok
  defp schedule_cleanup(%State{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%State{cleanup_interval_ms: interval}) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end
end