# Reconstruct the missing typespec

In the otherwise-complete module below, the `@spec` for
`get_payments/1` has been removed; `# TODO: @spec` holds its place.
Write that one attribute — a `@spec` for `get_payments/1` faithful to
the arguments, guards, and every return shape the code can actually
produce. Nothing else changes.

## The module with the `@spec` for `get_payments/1` missing

```elixir
defmodule BoundedIdempotentPayments do
  @moduledoc """
  A GenServer that simulates an idempotent payment system whose idempotency store
  is capacity-bounded with least-recently-used eviction instead of TTL expiry.
  Recency is tracked with an internal monotonic tick. Payment records themselves
  are never evicted.
  """

  use GenServer

  @default_max_keys 1000

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the server. Accepts `:max_keys` (a positive integer, default 1000) and
  `:clock` (a zero-arity ms clock). Raises `ArgumentError` when `:max_keys` is
  not a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    max_keys = Keyword.get(opts, :max_keys, @default_max_keys)

    unless is_integer(max_keys) and max_keys > 0 do
      raise ArgumentError, ":max_keys must be a positive integer"
    end

    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Processes a payment. With `nil` key a new record is always created; with a key,
  a cached result is returned (and its recency refreshed) or the payment is
  processed and stored under LRU bounds.
  """
  @spec process_payment(GenServer.server(), map(), String.t() | nil) ::
          {:ok, map()} | {:error, :invalid_params}
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end

  @doc "Returns all payment records, oldest first."
  # TODO: @spec
  def get_payments(server), do: GenServer.call(server, :get_payments)

  @doc "Fetches a payment record by id."
  @spec get_payment(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_payment(server, id), do: GenServer.call(server, {:get_payment, id})

  @doc "Returns retained idempotency keys ordered least-recently-used first."
  @spec keys_by_recency(GenServer.server()) :: [String.t()]
  def keys_by_recency(server), do: GenServer.call(server, :keys_by_recency)

  # --------------------------------------------------------------------------
  # Callbacks
  # --------------------------------------------------------------------------

  @impl true
  def init(opts) do
    max_keys = Keyword.get(opts, :max_keys, @default_max_keys)

    state = %{
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      max_keys: max_keys,
      tick: 0,
      counter: 0,
      payments: [],
      # key => {result, last_used_tick}
      idempotency_keys: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:process_payment, params, nil}, _from, state) do
    {result, state} = do_process(state, params)
    {:reply, result, state}
  end

  def handle_call({:process_payment, params, key}, _from, state) do
    case Map.get(state.idempotency_keys, key) do
      {result, _tick} ->
        # Cache hit: return cached result and refresh recency.
        {tick, state} = next_tick(state)
        keys = Map.put(state.idempotency_keys, key, {result, tick})
        {:reply, result, %{state | idempotency_keys: keys}}

      nil ->
        {result, state} = do_process(state, params)
        state = insert_key(state, key, result)
        {:reply, result, state}
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

  def handle_call(:keys_by_recency, _from, state) do
    keys =
      state.idempotency_keys
      |> Enum.sort_by(fn {_key, {_result, tick}} -> tick end)
      |> Enum.map(fn {key, _} -> key end)

    {:reply, keys, state}
  end

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

  defp insert_key(state, key, result) do
    state =
      if map_size(state.idempotency_keys) >= state.max_keys do
        evict_lru(state)
      else
        state
      end

    {tick, state} = next_tick(state)
    %{state | idempotency_keys: Map.put(state.idempotency_keys, key, {result, tick})}
  end

  defp evict_lru(state) do
    {lru_key, _} =
      Enum.min_by(state.idempotency_keys, fn {_key, {_result, tick}} -> tick end)

    %{state | idempotency_keys: Map.delete(state.idempotency_keys, lru_key)}
  end

  defp next_tick(state) do
    tick = state.tick + 1
    {tick, %{state | tick: tick}}
  end

  defp valid_params?(params) do
    is_map(params) and
      Map.has_key?(params, :amount) and
      Map.has_key?(params, :currency) and
      Map.has_key?(params, :recipient)
  end
end
```

Reply with the `@spec` attribute alone, however many lines it needs —
not the module.
