# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule IdempotentPayments do
  use GenServer

  @default_ttl_ms 86_400_000
  @default_cleanup_interval_ms 60_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end

  def get_payments(server) do
    GenServer.call(server, :get_payments)
  end

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
