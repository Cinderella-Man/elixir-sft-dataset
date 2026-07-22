# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me an Elixir GenServer module called `CoalescingPayments` that simulates an idempotent payment processing system with in-memory storage **and in-flight request coalescing**. Unlike a plain idempotent endpoint, the defining property here is the concurrency model: when several callers hit the same idempotency key *while the first one is still being processed*, only ONE payment is processed and all the concurrent waiters receive that single shared result.

Public API:

- `CoalescingPayments.start_link(opts)` to start the process. It should accept a `:clock` option (zero-arity function returning current time in milliseconds, default `fn -> System.monotonic_time(:millisecond) end`), `:ttl_ms` for how long completed idempotency keys are remembered (default 86,400,000), `:cleanup_interval_ms` (default 60,000, controlling periodic purge of expired *completed* entries via `Process.send_after`; `:infinity` disables it), and `:processor` — a one-arity function that receives `params` and returns `:ok` (payment accepted) or `{:error, reason}` (gateway declined). This function simulates the slow external call and defaults to `fn _params -> :ok end`.

- `CoalescingPayments.process_payment(server, params, idempotency_key \\ nil)` where `params` is a map with `:amount` (integer cents), `:currency` (string), and `:recipient` (string). Semantics:
  1. If `idempotency_key` is `nil`, always process a new payment (each call runs the processor independently) and return `{:ok, response}` or `{:error, reason}`.
  2. If the key is already **completed** (cached, not expired), return the exact same cached result without re-running the processor.
  3. If the key is currently **in flight** (another caller triggered processing that hasn't finished), the caller must block until that processing completes and then receive the same result — the processor must run exactly once for the whole group.
  4. If the key is expired or unseen, start processing.
  5. If required fields are missing, return `{:error, :invalid_params}` immediately (no processor call) and, when a key was given, cache that error result too.

  The GenServer must NOT block inside the processor — run the processor work in a spawned process and reply to all waiting callers via `GenServer.reply/2` when it finishes. A successful result builds a `response` map with `:id` (unique string like `"pay_1"`, counter-based), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (timestamp from the clock).

- `CoalescingPayments.get_payments(server)` returns all payment records (oldest first).
- `CoalescingPayments.get_payment(server, id)` returns `{:ok, payment}` or `{:error, :not_found}`.
- `CoalescingPayments.in_flight_count(server)` returns how many payments are currently being processed (pending, not yet replied).

Payment records are never cleaned up; only expired *completed* idempotency entries are purged on the `:cleanup` message. Use only the OTP standard library; no external dependencies. Give me the complete module in a single file.

## Module under test

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
