# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `get_payments` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `CoalescingPayments` that simulates an idempotent payment processing system with in-memory storage **and in-flight request coalescing**. Unlike a plain idempotent endpoint, the defining property here is the concurrency model: when several callers hit the same idempotency key *while the first one is still being processed*, only ONE payment is processed and all the concurrent waiters receive that single shared result.

## Public API

### `CoalescingPayments.start_link(opts)`

Starts the process. `opts` is a keyword list; it must default to `[]` so `start_link()` works with no arguments. Options:

- `:clock` — zero-arity function returning current time in milliseconds. Default `fn -> System.monotonic_time(:millisecond) end`. Every timestamp and every TTL comparison in the module must come from this function, so a test clock fully controls time.
- `:ttl_ms` — how long a completed idempotency key is remembered. Default `86_400_000`.
- `:cleanup_interval_ms` — default `60_000`. Schedules a recurring `:cleanup` message via `Process.send_after/3` (scheduled once at init and re-scheduled after each `:cleanup` is handled). The value `:infinity` disables scheduling entirely — no `:cleanup` message is ever sent by the server itself.
- `:processor` — one-arity function receiving `params`, returning `:ok` (payment accepted) or `{:error, reason}` (gateway declined). Simulates the slow external call. Default `fn _params -> :ok end`.
- `:name` — if present, forwarded to `GenServer.start_link/3` as the name registration option. Any other keys in `opts` are ignored.

### `CoalescingPayments.process_payment(server, params, idempotency_key \\ nil)`

`params` is a map expected to have `:amount` (integer cents), `:currency` (string) and `:recipient` (string). The call must use a client-side timeout of 30 seconds (not the default 5 s), since a coalesced caller may wait for a slow processor.

Returns `{:ok, response}` or `{:error, reason}`.

**Validation.** `params` is *valid* only if it is a map that has all three keys `:amount`, `:currency` and `:recipient`. Values are never inspected — no type or range checks; `%{amount: -5, currency: nil, recipient: ""}` is valid. Extra keys are allowed and simply ignored. An invalid `params` yields `{:error, :invalid_params}` immediately, without ever calling the processor:

- with `idempotency_key == nil`: returned, nothing stored;
- with a key: `{:error, :invalid_params}` is also **cached as a completed entry** for that key with the normal TTL, so later calls with the same key return `{:error, :invalid_params}` from cache even if they pass valid params.

**Semantics with `idempotency_key == nil`.** Every call processes a new payment independently — no caching, no coalescing, even for two identical `params` maps. Concurrent nil-key calls each get their own result.

**Semantics with an idempotency key** (any term, typically a string — the key is used as-is as a map key, never inspected):

1. **Completed and not expired** — an entry exists whose expiry is *strictly greater than* the current clock value: return the exact cached result (the same `{:ok, response}` tuple, including the original `:id` and `:created_at`) without re-running the processor. An entry whose expiry is exactly equal to `now` is treated as expired.
2. **Pending (in flight)** — another caller triggered processing for this key and it has not finished: the caller blocks (no reply yet) and is added to the waiter list for that key. When the work finishes, every waiter — including the original caller — receives the same result via `GenServer.reply/2`. The processor runs **exactly once** for the whole group, and only **one** payment record is created. Note that a pending entry short-circuits before validation: a later caller joining a pending key gets the group's result regardless of the `params` it passed, and those params are discarded.
3. **Unseen key, or completed-but-expired key** — validate the params and start fresh processing; an expired entry is simply overwritten.

**Non-blocking requirement.** The GenServer must never block inside the processor. Run the processor in a spawned process, which sends the outcome back to the server; the server then replies to all waiting callers with `GenServer.reply/2`. While work is in flight, the server must keep serving other calls (`get_payments/1`, `in_flight_count/1`, other keys, etc.).

**Processor exceptions.** If the processor raises, the spawned worker rescues it and the outcome becomes `{:error, {:exception, message}}` where `message` is `Exception.message/1` of the raised exception. The caller (and any coalesced waiters) get that error tuple; it is cached like any other result when a key was given. The server does not crash.

**Result construction.** When the processor returns `:ok`, the server increments an integer counter (starting at 0) and builds:

- `:id` — `"pay_N"` where N is the new counter value, so the first successful payment is `"pay_1"`, the second `"pay_2"`, and so on. Only *successful* payments consume a counter value; a declined or invalid payment does not.
- `:amount`, `:currency`, `:recipient` — copied from `params`.
- `:status` — always the string `"completed"`.
- `:created_at` — the clock value read at the moment the result is finalized (i.e. when the worker's outcome is handled, not when the request arrived).

The response map is appended to the payment records and returned as `{:ok, response}`. When the processor returns `{:error, reason}`, the caller gets `{:error, reason}` verbatim, no counter is consumed and no payment record is stored.

**Caching of results.** For a keyed request, the result (success *or* error, including gateway declines and processor exceptions) is stored as a completed entry with expiry `clock.() + ttl_ms`, computed when the work finishes. From then on, repeated calls with that key return the cached result until expiry.

### `CoalescingPayments.get_payments(server)`

Returns the list of all payment records **oldest first**. Returns `[]` when none exist. Only successful payments appear here.

### `CoalescingPayments.get_payment(server, id)`

Returns `{:ok, payment}` for a matching `:id`, or `{:error, :not_found}` for any unknown id.

### `CoalescingPayments.in_flight_count(server)`

Returns a non-negative integer: the number of payment requests currently being processed and not yet replied to. This counts both keyed requests in the pending state and nil-key requests still awaiting their worker. A coalesced group of N waiters on one key counts as **1**. The count drops back as each unit of work is finalized, so once everything settles it returns `0`. Requests rejected as `:invalid_params` never enter this count.

## Cleanup

Payment records are **never** removed — neither by TTL nor by cleanup. The `:cleanup` message only purges idempotency entries that are *completed and expired* (expiry not strictly greater than the current clock). Pending entries are always kept, no matter how long they have been in flight. Cleanup is purely an optimization: an expired entry that has not yet been purged must still behave as expired when a call hits it. Unknown/unexpected messages sent to the server must be ignored without crashing.

Use only the OTP standard library; no external dependencies. Give me the complete module in a single file.

## The module with `get_payments` missing

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

  def get_payments(server) do
    # TODO
  end

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

Give me only the complete implementation of `get_payments` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
