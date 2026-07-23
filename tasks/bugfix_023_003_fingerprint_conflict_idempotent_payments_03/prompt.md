# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

Hey — I need you to write me an Elixir GenServer module called `StrictIdempotentPayments`. The idea is to simulate an idempotent payment processing system with in-memory storage, but with a twist I care about a lot: request-fingerprint conflict detection. Here's the key behavioral difference from a naive idempotent endpoint — if someone replays an idempotency key with a *different request body*, I want that treated as a client error rather than silently returning the original cached response.

For the public API, start with `StrictIdempotentPayments.start_link(opts)`. It should accept `:clock` (a zero-arity ms clock, defaulting to `fn -> System.monotonic_time(:millisecond) end`), `:ttl_ms` (default 86,400,000), and `:cleanup_interval_ms` (default 60,000; passing `:infinity` disables the periodic `:cleanup` purge that otherwise runs via `Process.send_after`).

Then I need `StrictIdempotentPayments.process_payment(server, params, idempotency_key \\ nil)`, where `params` is a map carrying `:amount` (integer cents), `:currency` (string), and `:recipient` (string). Each stored idempotency entry should record the cached result, a fingerprint of the request params (compute it deterministically, e.g. `:erlang.phash2(params)`), and an expiry timestamp. An entry stored at clock time `T` expires at `T + ttl_ms`, and it counts as expired once the clock reaches that timestamp — so it's valid only while the current clock reading is strictly less than `T + ttl_ms`, meaning a replay at exactly `T + ttl_ms` gets processed fresh rather than served from cache. The semantics I want are:

1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
2. If the key has been seen and isn't expired and the current params fingerprint matches the stored one, return the exact cached result.
3. If the key has been seen and isn't expired but the params fingerprint differs, return `{:error, :idempotency_key_conflict}` — don't return the cached response, don't create a new record, and don't mutate the stored entry.
4. If the key is expired or unseen, process it normally (fingerprint the new params), cache the result under the key with a TTL, and return it.
5. If required fields are missing, return `{:error, :invalid_params}`; and when a key was provided, cache that error result along with its fingerprint — so a same-params replay returns the same error, while a different-params replay under that key is a conflict.

A successful `response` map should contain `:id` (a counter-based unique string; the first record created is `"pay_1"`, the next `"pay_2"`, and so on — the counter advances only when a record is actually created), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (the clock timestamp).

I also want `StrictIdempotentPayments.get_payments(server)` to return all payment records as a list, oldest first (an empty list when there are none), and `StrictIdempotentPayments.get_payment(server, id)` to return `{:ok, payment}` or `{:error, :not_found}`.

The periodic `:cleanup` should remove only expired idempotency entries (again, an entry is expired once the clock has reached its expiry timestamp); payment records must never be removed. And sending `:cleanup` to the server must never crash it. Please use only the OTP standard library, and give me the complete module in a single file.

## The buggy module

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
      {result, stored_fp, expiry} when expiry >= now ->
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

  # Arms the next periodic purge (when enabled) and returns the state unchanged,
  # so it can be threaded through `init/1` and `handle_info/2`.
  defp schedule_cleanup(%{cleanup_interval_ms: :infinity} = state), do: state

  defp schedule_cleanup(%{cleanup_interval_ms: interval} = state) when is_integer(interval) do
    Process.send_after(self(), :cleanup, interval)
    state
  end
end
```

## Failing test report

```
1 of 19 test(s) failed:

  * test key is expired exactly at the ttl boundary
      
      
      Assertion with != failed, both sides are exactly equal
      code: assert second.id != first.id
      left: "pay_1"
```
