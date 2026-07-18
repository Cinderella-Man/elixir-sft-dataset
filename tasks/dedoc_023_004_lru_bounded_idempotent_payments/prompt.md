# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule BoundedIdempotentPayments do
  use GenServer

  @default_max_keys 1000

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  def start_link(opts \\ []) do
    max_keys = Keyword.get(opts, :max_keys, @default_max_keys)

    unless is_integer(max_keys) and max_keys > 0 do
      raise ArgumentError, ":max_keys must be a positive integer"
    end

    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end

  def get_payments(server), do: GenServer.call(server, :get_payments)

  def get_payment(server, id), do: GenServer.call(server, {:get_payment, id})

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
